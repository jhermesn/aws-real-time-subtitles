from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import CloudFront
from diagrams.aws.security import WAF, Cognito
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
    "pad": "2.0",
    "splines": "curved",
    "nodesep": "1.2",
    "ranksep": "2.2",
    "bgcolor": "white",
    "margin": "0.8",
}

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
            waf    = WAF("WAF v2\nIP allowlist\n/admin + /api/*")
            cf     = CloudFront("CloudFront")
            cf_fn  = LambdaFunction("CF Function\nspeaker-auth\n(HMAC + expiry)")

        with Cluster("Origins"):
            s3   = S3("S3\nReact App\n(OAC)")
            sign = Lambda("Lambda\nsign-room\n(X-CF-Secret)")

        with Cluster("AI Services"):
            cognito    = Cognito("Cognito\nIdentity Pool\n(unauthenticated)")
            transcribe = Transcribe("Transcribe\nStreaming")
            translate  = Translate("Translate")

    # --- Admin flow ---
    organizer >> Edge(color=BLUE, label="① POST /api/sign-room") >> waf
    waf >> Edge(color=BLUE) >> cf
    cf >> Edge(color=BLUE, label="X-CF-Secret header") >> sign
    sign >> Edge(color=BLUE, style="dashed", constraint="false", headlabel="② signed token") >> organizer

    # --- Static assets ---
    cf >> Edge(color=GRAY, style="dashed", label="/* → S3 OAC") >> s3

    # --- Admin hands off URL ---
    organizer >> Edge(color=GRAY, style="dashed", label="③ speaker URL") >> speaker

    # --- Speaker flow ---
    speaker >> Edge(color=ORANGE, label="④ /speaker?token=") >> waf
    waf >> Edge(color=ORANGE) >> cf
    cf >> Edge(color=ORANGE, label="viewer-request") >> cf_fn
    cf_fn >> Edge(color=ORANGE, style="dashed", label="token OK → serve") >> s3

    # --- Speaker AI flow ---
    speaker >> Edge(color=GREEN, label="temp creds") >> cognito
    speaker >> Edge(color=GREEN, label="audio stream") >> transcribe
    transcribe >> Edge(color=GREEN, label="transcript") >> translate
    translate >> Edge(color=GREEN, constraint="false", headlabel="⑤ subtitles") >> speaker

    # --- Audience ---
    speaker >> Edge(color=GRAY, style="dashed", label="screen share") >> audience
