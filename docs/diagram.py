from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import CloudFront
from diagrams.aws.security import WAF, IAMAWSSts
from diagrams.aws.storage import S3
from diagrams.aws.compute import Lambda, LambdaFunction
from diagrams.aws.ml import Transcribe, Translate
from diagrams.onprem.client import User, Users

BLUE   = "#2d6de1"
ORANGE = "#e8822c"
GRAY   = "#888888"
GREEN  = "#1d8348"

graph_attr = {
    "fontsize": "14",
    "pad": "1.0",
    "splines": "line",
    "nodesep": "1.2",
    "ranksep": "1.8",
    "bgcolor": "white",
    "margin": "0.6",
    "labelloc": "t",
}

edge_attr = {"dir": "both", "arrowtail": "none"}

with Diagram(
    "AWS Real-Time Subtitles",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    organizer = User("Organizer\n(Admin)")
    speaker   = User("Speaker")
    audience  = Users("Audience\n(screen share)")

    with Cluster("AWS Cloud"):

        with Cluster("Edge — us-east-1"):
            waf   = WAF("WAF v2\n(optional, off by default)")
            cf    = CloudFront("CloudFront")
            cf_fn = LambdaFunction("CF Function: speaker-auth\nIP allowlist + HMAC token")

        with Cluster("Origins"):
            s3   = S3("S3\nReact App (OAC)")
            sign = Lambda("Lambda: sign-room\n(OAC-signed origin)")

        with Cluster("AI Services"):
            sts        = IAMAWSSts("STS AssumeRole\nspeaker-session role")
            transcribe = Transcribe("Transcribe\nStreaming")
            translate  = Translate("Translate\n(skipped if src == tgt)")

    # --- Admin: create room. Arrowheads on both ends: request out, token back. ---
    organizer >> Edge(color=GRAY, style="dashed", label="(optional) WAF layer", **edge_attr) >> waf
    waf >> Edge(color=BLUE, label="POST /api/sign-room\n(returns signed token)", **edge_attr) >> cf
    cf >> Edge(color=BLUE, label="OAC-signed", **edge_attr) >> sign
    organizer >> Edge(color=GRAY, style="dashed", label="shares speaker URL") >> speaker

    # --- Static assets ---
    cf >> Edge(color=GRAY, style="dashed", label="/*") >> s3

    # --- Speaker: page load ---
    speaker >> Edge(color=ORANGE, label="/speaker?token=") >> cf
    cf >> Edge(color=ORANGE, label="viewer-request") >> cf_fn
    cf_fn >> Edge(color=ORANGE, style="dashed", label="token OK, serve SPA") >> s3

    # --- Speaker: credential vending (same CloudFront + Lambda origin) ---
    speaker >> Edge(color=GREEN, label="GET /api/session\nX-Room-Token header\n(returns temp credentials)", **edge_attr) >> cf
    sign >> Edge(color=GREEN, label="AssumeRole", **edge_attr) >> sts

    # --- Speaker: streaming ---
    speaker >> Edge(color=GREEN, label="audio stream\n(returns subtitles)", **edge_attr) >> transcribe
    transcribe >> Edge(color=GREEN, label="transcript") >> translate

    # --- Audience ---
    speaker >> Edge(color=GRAY, style="dashed", label="screen share") >> audience
