import os, json, time, base64, boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ["PREFIX"]

ROUTES = {
    "/": ("index.html", "text/html"),
    "/index.html": ("index.html", "text/html"),
    "/style.css": ("style.css", "text/css"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}

def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")
    if path in ROUTES:
        name, ctype = ROUTES[path]
        data = s3.get_object(Bucket=BUCKET, Key=PREFIX + name)["Body"].read()
        headers = {"Content-Type": ctype}
        if name == "index.html":
            text = data.decode("utf-8").replace(
                "{{HOSTED_ON}}", f"Lambda {context.function_name}")
            headers["Cache-Control"] = "max-age=60"
            resp = {"statusCode": 200, "headers": headers, "body": text}
        elif name == "cv.pdf":
            resp = {"statusCode": 200, "headers": headers,
                    "isBase64Encoded": True,
                    "body": base64.b64encode(data).decode()}
        else:
            resp = {"statusCode": 200, "headers": headers,
                    "body": data.decode("utf-8")}
    else:
        resp = {"statusCode": 404,
                "headers": {"Content-Type": "text/html"},
                "body": "<h1>404</h1><p>Not found.</p>"}
    print(json.dumps({"fn": context.function_name, "path": path,
                      "status": resp["statusCode"],
                      "ms": int((time.time() - start) * 1000)}))
    return resp
