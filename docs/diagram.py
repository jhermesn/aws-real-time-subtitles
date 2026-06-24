from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import CloudFront
from diagrams.aws.security import WAF, Cognito
from diagrams.aws.storage import S3
from diagrams.aws.compute import Lambda
from diagrams.aws.ml import Transcribe, Translate
from diagrams.onprem.client import User, Users

BLUE   = "#2d6de1"
ORANGE = "#e8822c"
GRAY   = "#888888"

graph_attr = {
    "fontsize": "13",
    "pad": "1.5",
    "splines": "curved",
    "nodesep": "0.9",
    "ranksep": "1.8",
    "bgcolor": "white",
    "margin": "0.5",
}

with Diagram(
    "AWS Real-Time Subtitles",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    organizer = User("Organizer")
    speaker   = User("Speaker")
    audience  = Users("Audience")

    with Cluster("AWS Cloud"):

        with Cluster("Edge (us-east-1)"):
            waf = WAF("WAF v2\nIP allowlist")
            cf  = CloudFront("CloudFront\nHMAC check")

        with Cluster("Origins"):
            s3   = S3("S3\nReact App")
            sign = Lambda("Lambda\nsign-room")

        with Cluster("AI Services"):
            cognito    = Cognito("Cognito\nIdentity Pool")
            transcribe = Transcribe("Transcribe\nStreaming")
            translate  = Translate("Translate")

    # 1: admin creates room
    organizer >> Edge(color=BLUE, label="1  POST /api/sign-room") >> waf
    waf >> Edge(color=BLUE) >> cf
    cf >> Edge(color=BLUE, style="dashed", label="/* S3") >> s3
    cf >> Edge(color=BLUE, label="/api/* OAC") >> sign
    sign >> Edge(color=BLUE, style="dashed", constraint="false", headlabel="2  token") >> organizer

    # 2: handoff
    organizer >> Edge(color=GRAY, style="dashed", label="3  speaker URL") >> speaker

    # 3: speaker opens URL
    speaker >> Edge(color=ORANGE, label="4  /speaker?token=") >> cf

    # 4: speaker browser calls AI services directly (Cognito creds enable this)
    speaker >> Edge(color=ORANGE) >> cognito
    cognito >> Edge(color=ORANGE, label="temp creds") >> transcribe
    transcribe >> Edge(color=ORANGE, label="transcript") >> translate
    translate >> Edge(color=ORANGE, constraint="false", headlabel="5  subtitles") >> speaker

    # 5: audience watches
    speaker >> Edge(color=GRAY, style="dashed", label="screen share") >> audience
