import json
import os
import sys
import tempfile
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow


SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/tasks",
]
CALENDAR_SCOPE = SCOPES[0]
TASKS_SCOPE = SCOPES[1]


def config():
    config_path = Path(
        os.environ.get("CADENCE_CONFIG_PATH", "~/.config/cadence/config.json")
    ).expanduser()
    if not config_path.exists():
        return {}
    with config_path.open() as file:
        return json.load(file)


def configured_path(values, key, default):
    value = values.get(key, default)
    return Path(os.path.expandvars(value)).expanduser()


def accounts(settings):
    configured_accounts = settings.get("accounts")
    if isinstance(configured_accounts, list):
        return [
            account
            for account in configured_accounts
            if isinstance(account, dict) and account.get("id")
        ]

    # Existing single-account configuration remains valid after upgrading.
    return [
        {
            "id": "default",
            "label": "Default",
            "credentialsPath": settings.get(
                "credentialsPath", "~/.config/cadence/credentials.json"
            ),
            "tokenPath": settings.get("tokenPath", "~/.cache/cadence/token.json"),
            "calendar": True,
            "tasks": True,
        }
    ]


def account_scopes(account):
    scopes = []
    if account.get("calendar"):
        scopes.append(CALENDAR_SCOPE)
    if account.get("tasks"):
        scopes.append(TASKS_SCOPE)
    return scopes


def authenticate(settings, account, scopes, force=False):
    cache_dir = configured_path(settings, "cacheDirectory", "~/.cache/cadence")
    credentials_path = configured_path(
        account, "credentialsPath", "~/.config/cadence/credentials.json"
    )
    token_path = configured_path(account, "tokenPath", str(cache_dir / "token.json"))

    cache_dir.mkdir(parents=True, exist_ok=True)
    token_path.parent.mkdir(parents=True, exist_ok=True)

    creds = None
    if token_path.exists() and not force:
        token_path.chmod(0o600)
        creds = Credentials.from_authorized_user_file(token_path)

    if not creds or not creds.valid or not creds.has_scopes(scopes):
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                creds = None

        if not creds or not creds.valid or not creds.has_scopes(scopes):
            if not credentials_path.exists():
                print(
                    json.dumps(
                        {
                            "error": (
                                "Missing Google OAuth credentials at "
                                f"{credentials_path} for {account['id']}."
                            )
                        }
                    )
                )
                raise RuntimeError("Google authorization required.")

            if "--background" in sys.argv:
                print(
                    json.dumps(
                        {
                            "error": (
                                "Google authentication expired. Run the Cadence "
                                "backend without --background to reconnect."
                            )
                        }
                    )
                )
                raise RuntimeError("Google authorization required.")

            flow = InstalledAppFlow.from_client_secrets_file(credentials_path, scopes)
            creds = flow.run_local_server(port=0, authorization_prompt_message=None)

        write_json(token_path, json.loads(creds.to_json()))

    return creds


def get_upcoming_events(creds, account, days_back=1):
    import datetime

    from googleapiclient.discovery import build

    service = build("calendar", "v3", credentials=creds)
    now_local = datetime.datetime.now().astimezone()
    midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    start_date = midnight - datetime.timedelta(days=days_back)
    end_date = now_local + datetime.timedelta(days=31)

    events = (
        service.events()
        .list(
            calendarId="primary",
            timeMin=start_date.isoformat(),
            timeMax=end_date.isoformat(),
            maxResults=250,
            singleEvents=True,
            orderBy="startTime",
        )
        .execute()
        .get("items", [])
    )

    output = []
    for event in events:
        reminders = event.get("reminders", {})
        reminder_minutes = []
        if reminders.get("useDefault"):
            reminder_minutes.append(10)
        else:
            for override in reminders.get("overrides", []):
                if override.get("method") == "popup":
                    reminder_minutes.append(override.get("minutes", 10))

        output.append(
            {
                "id": event.get("id", ""),
                "accountId": account["id"],
                "account": account.get("label", account["id"]),
                "title": event.get("summary", "Busy"),
                "description": event.get("description", ""),
                "start": event["start"].get("dateTime", event["start"].get("date")),
                "end": event["end"].get("dateTime", event["end"].get("date")),
                "link": event.get("htmlLink", ""),
                "meetLink": meet_link(event),
                "rsvp": rsvp_status(event),
                "reminders": reminder_minutes,
            }
        )
    return output


def meet_link(event):
    for entry_point in event.get("conferenceData", {}).get("entryPoints", []):
        if entry_point.get("entryPointType") == "video" and entry_point.get("uri"):
            return entry_point["uri"]
    return event.get("hangoutLink", "")


def rsvp_status(event):
    attendees = event.get("attendees")
    if not attendees:
        return "none"
    for attendee in attendees:
        if attendee.get("self"):
            return attendee.get("responseStatus", "needsAction")
    return "none"


def task_object(account, task_list, task):
    return {
        "id": task.get("id"),
        "accountId": account["id"],
        "listId": task_list["id"],
        "list": task_list.get("title", "Tasks"),
        "title": task.get("title", "") or "(no title)",
        "notes": task.get("notes", ""),
        "due": task.get("due"),
        "completed": task.get("completed"),
        "status": task.get("status", "needsAction"),
        "link": task.get("webViewLink", ""),
    }


def list_tasks(service, task_list_id, **kwargs):
    tasks = []
    page_token = None
    while True:
        response = (
            service.tasks()
            .list(
                tasklist=task_list_id,
                maxResults=100,
                pageToken=page_token,
                **kwargs,
            )
            .execute()
        )
        tasks.extend(response.get("items", []))
        page_token = response.get("nextPageToken")
        if not page_token:
            return tasks


def get_tasks(creds, account, completed_days):
    import datetime

    from googleapiclient.discovery import build

    service = build("tasks", "v1", credentials=creds)
    now_local = datetime.datetime.now().astimezone()
    midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    completed_min = (midnight - datetime.timedelta(days=completed_days)).isoformat()

    output = []
    task_lists = service.tasklists().list(maxResults=100).execute().get("items", [])
    for task_list in task_lists:
        for task in list_tasks(
            service, task_list["id"], showCompleted=False, showHidden=False
        ):
            output.append(task_object(account, task_list, task))
        for task in list_tasks(
            service,
            task_list["id"],
            showCompleted=True,
            showHidden=True,
            completedMin=completed_min,
        ):
            if task.get("status") == "completed":
                output.append(task_object(account, task_list, task))
    return output


def set_task_status(creds, task_list_id, task_id, status):
    from googleapiclient.discovery import build

    body = {"status": status}
    if status != "completed":
        body["completed"] = None
    service = build("tasks", "v1", credentials=creds)
    service.tasks().patch(tasklist=task_list_id, task=task_id, body=body).execute()
    return {"ok": True}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, delete=False, encoding="utf-8"
    ) as file:
        json.dump(value, file, indent=2)
        file.write("\n")
        temporary_path = Path(file.name)
    temporary_path.replace(path)


def sync(settings):
    cache_dir = configured_path(settings, "cacheDirectory", "~/.cache/cadence")
    completed_days = settings.get("completedTaskDays", 1)
    events = []
    tasks = []
    calendar_synced = False
    tasks_synced = False
    errors = []

    for account in accounts(settings):
        scopes = account_scopes(account)
        if not scopes:
            continue
        label = account.get("label", account["id"])
        try:
            creds = authenticate(settings, account, scopes)
        except Exception as error:
            errors.append(f"{label}: authentication failed ({type(error).__name__})")
            continue

        if account.get("calendar"):
            try:
                events.extend(get_upcoming_events(creds, account))
                calendar_synced = True
            except Exception as error:
                errors.append(f"{label}: Calendar sync failed ({type(error).__name__})")
        if account.get("tasks"):
            try:
                tasks.extend(get_tasks(creds, account, completed_days))
                tasks_synced = True
            except Exception as error:
                errors.append(f"{label}: Tasks sync failed ({type(error).__name__})")

    if calendar_synced:
        write_json(cache_dir / "events.json", events)
    if tasks_synced:
        write_json(cache_dir / "tasks.json", tasks)
    if not calendar_synced and not tasks_synced:
        raise RuntimeError("No Cadence data source could be synchronized.")

    result = {"events": len(events), "tasks": len(tasks), "errors": errors}
    if errors:
        print(json.dumps(result), file=sys.stderr)
    else:
        print(json.dumps(result))


def account_for_id(settings, account_id):
    for account in accounts(settings):
        if account["id"] == account_id:
            return account
    raise ValueError(f"Unknown Cadence account: {account_id}")


def main():
    settings = config()

    if "--authenticate" in sys.argv:
        index = sys.argv.index("--authenticate")
        account = account_for_id(settings, sys.argv[index + 1])
        scopes = account_scopes(account)
        if not scopes:
            raise ValueError(f"Calendar and Tasks are disabled for: {account['id']}")
        authenticate(settings, account, scopes, force=True)
        print(json.dumps({"account": account["id"], "connected": True}))
        return

    if "--set-status" in sys.argv:
        index = sys.argv.index("--set-status")
        account_id, task_list_id, task_id, status = sys.argv[index + 1 : index + 5]
        account = account_for_id(settings, account_id)
        if not account.get("tasks"):
            raise ValueError(f"Tasks are disabled for Cadence account: {account_id}")
        creds = authenticate(settings, account, [TASKS_SCOPE])
        print(json.dumps(set_task_status(creds, task_list_id, task_id, status)))
        return

    if "--sync" in sys.argv:
        sync(settings)
        return

    if "--tasks" in sys.argv:
        completed_days = settings.get("completedTaskDays", 1)
        output = []
        for account in accounts(settings):
            if account.get("tasks"):
                creds = authenticate(settings, account, [TASKS_SCOPE])
                output.extend(get_tasks(creds, account, completed_days))
        print(json.dumps(output, indent=2))
        return

    output = []
    for account in accounts(settings):
        if account.get("calendar"):
            creds = authenticate(settings, account, [CALENDAR_SCOPE])
            output.extend(get_upcoming_events(creds, account))
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
