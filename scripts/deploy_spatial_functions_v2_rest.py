#!/usr/bin/env python3
import json
import os
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

PROJECT_ID = os.environ.get("PROJECT_ID", "amen-5e359")
REGION = os.environ.get("FUNCTION_REGION", "us-central1")
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Backend" / "spatial-functions"
ADC_PATH = Path(os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", Path.home() / ".config/gcloud/application_default_credentials.json"))

HTTP_FUNCTIONS = [
    "createCovenantSpatialRoom",
    "generateSpatialRoomTheme",
    "backfillCovenantSpatialRooms",
]

EVENT_FUNCTIONS = {
    "onCovenantRoomMessageCreatedUpdateAmbientState": {
        "eventType": "google.cloud.firestore.document.v1.created",
        "document": "covenants/{covenantId}/rooms/{roomId}/messages/{messageId}",
    }
}


def access_token() -> str:
    adc = json.loads(ADC_PATH.read_text())
    data = urllib.parse.urlencode({
        "refresh_token": adc["refresh_token"],
        "client_id": adc["client_id"],
        "client_secret": adc["client_secret"],
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=60).read())["access_token"]


def api(method: str, url: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {access_token()}",
            "Content-Type": "application/json",
        },
    )
    return json.loads(urllib.request.urlopen(req, timeout=120).read() or b"{}")


def zip_source() -> Path:
    fd, archive_name = tempfile.mkstemp(prefix="amen-spatial-functions-", suffix=".zip")
    os.close(fd)
    archive = Path(archive_name)
    include_roots = ["lib", "src"]
    include_files = ["package.json", "package-lock.json", "tsconfig.json"]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for file_name in include_files:
            path = SOURCE / file_name
            if path.exists():
                zf.write(path, file_name)
        for root_name in include_roots:
            root = SOURCE / root_name
            if not root.exists():
                continue
            for path in root.rglob("*"):
                if path.is_file():
                    zf.write(path, path.relative_to(SOURCE).as_posix())
    return archive


def upload_source(archive: Path) -> dict:
    parent = f"projects/{PROJECT_ID}/locations/{REGION}"
    upload = api("POST", f"https://cloudfunctions.googleapis.com/v2/{parent}/functions:generateUploadUrl", {"environment": "GEN_2"})
    upload_url = upload["uploadUrl"]
    req = urllib.request.Request(
        upload_url,
        data=archive.read_bytes(),
        method="PUT",
        headers={"Content-Type": "application/zip"},
    )
    urllib.request.urlopen(req, timeout=300).read()
    return upload["storageSource"]


def operation_wait(operation_name: str):
    url = f"https://cloudfunctions.googleapis.com/v2/{operation_name}"
    for _ in range(120):
        op = api("GET", url)
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(json.dumps(op["error"], indent=2))
            return op
        time.sleep(5)
    raise TimeoutError(operation_name)


def base_function(function_id: str, storage_source: dict) -> dict:
    return {
        "name": f"projects/{PROJECT_ID}/locations/{REGION}/functions/{function_id}",
        "buildConfig": {
            "runtime": "nodejs22",
            "entryPoint": function_id,
            "source": {"storageSource": storage_source},
        },
        "serviceConfig": {
            "availableMemory": "512M",
            "timeoutSeconds": 120,
            "maxInstanceCount": 20,
            "secretEnvironmentVariables": [
                {
                    "key": "OPENAI_API_KEY",
                    "projectId": PROJECT_ID,
                    "secret": "OPENAI_API_KEY",
                    "version": "latest",
                }
            ],
        },
        "labels": {
            "firebase-functions-codebase": "spatial",
            "deployment-tool": "amen-direct-v2",
        },
    }


def upsert_function(function_id: str, payload: dict):
    name = f"projects/{PROJECT_ID}/locations/{REGION}/functions/{function_id}"
    exists = True
    try:
        api("GET", f"https://cloudfunctions.googleapis.com/v2/{name}")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            exists = False
        else:
            raise

    if exists:
        update_mask = ",".join([
            "buildConfig.runtime",
            "buildConfig.entryPoint",
            "buildConfig.source.storageSource",
            "serviceConfig.availableMemory",
            "serviceConfig.timeoutSeconds",
            "serviceConfig.maxInstanceCount",
            "serviceConfig.secretEnvironmentVariables",
            "labels",
        ])
        if "eventTrigger" in payload:
            update_mask += ",eventTrigger"
        else:
            update_mask += ",serviceConfig.ingressSettings"
        op = api("PATCH", f"https://cloudfunctions.googleapis.com/v2/{name}?updateMask={urllib.parse.quote(update_mask)}", payload)
    else:
        parent = f"projects/{PROJECT_ID}/locations/{REGION}"
        op = api("POST", f"https://cloudfunctions.googleapis.com/v2/{parent}/functions?functionId={function_id}", payload)
    print(f"{'Updating' if exists else 'Creating'} {function_id}: {op.get('name')}")
    operation_wait(op["name"])


def main():
    archive = zip_source()
    try:
        storage_source = upload_source(archive)
        for function_id in HTTP_FUNCTIONS:
            payload = base_function(function_id, storage_source)
            payload["serviceConfig"]["ingressSettings"] = "ALLOW_ALL"
            upsert_function(function_id, payload)

        for function_id, config in EVENT_FUNCTIONS.items():
            payload = base_function(function_id, storage_source)
            payload["eventTrigger"] = {
                "triggerRegion": "nam5",
                "eventType": config["eventType"],
                "eventFilters": [
                    {"attribute": "database", "value": "(default)"},
                    {"attribute": "namespace", "value": "(default)"},
                ],
                "eventFilterPathPatterns": [
                    {"attribute": "document", "value": config["document"]},
                ],
                "retryPolicy": "RETRY_POLICY_DO_NOT_RETRY",
            }
            upsert_function(function_id, payload)
    finally:
        archive.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
