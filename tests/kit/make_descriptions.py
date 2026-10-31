"""The project pages' descriptions, ready to paste: release/description.md with each IMAGE_...
placeholder replaced by the address the site gave that gallery image, written to
release/description-curseforge.md and release/description-wago.md. After uploading a new or
changed gallery image, put its two addresses below and run this again.

python tests/kit/make_descriptions.py
"""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RELEASE = os.path.join(ROOT, "release")
CF = "https://media.forgecdn.net/attachments/2130/"
WAGO = "https://cdn.wago.io/gallery/"

# Each placeholder: its gallery image, then its address on CurseForge and on Wago (in the order
# they were uploaded, the cover first).
IMAGES = {
    "IMAGE_GO_LIVE": ("01-go-live.png", CF + "703/01-go-live-png.png",
                      WAGO + "xiTeyFdPWsGCeC5iuKOrFZ7uXeBJw3JDal8RUBNs.png"),
    "IMAGE_HOW_IT_WORKS": ("00-how-it-works.gif", CF + "704/00-how-it-works-gif.gif",
                           WAGO + "IFLWzMXJkfPTnr8UqtU047XjRDGXuXfopjlgNnMw.gif"),
    "IMAGE_ALIASES": ("02-aliases.png", CF + "705/02-aliases-png.png",
                      WAGO + "CPqb8jYPaXponisixqyoDYa5V6FPl7yIhe4u8pv5.png"),
    "IMAGE_FRAMES": ("shot-frames.png", CF + "706/shot-frames-png.png",
                     WAGO + "0u700Rb6PZw7C0lnSMQqDuKeE5e52unYlIYGpItG.png"),
    "IMAGE_METERS": ("shot-meters.png", CF + "707/shot-meters-png.png",
                     WAGO + "YkPUhNwkEyYqqwK7qcLhiBddrbU6YGWfrHHQQmrZ.png"),
    "IMAGE_EVERYWHERE": ("03-everywhere.png", CF + "708/03-everywhere-png.png",
                         WAGO + "SOuv5SbNIHzB6OOyfIDA9hf30dMJqclDfXgm7lRC.png"),
    "IMAGE_MOMENTS": ("04-moments.png", CF + "709/04-moments-png.png",
                      WAGO + "pcvqguQ1B9H5uuhPknB7uVbXwZRPzI2SJUS7bBSZ.png"),
    "IMAGE_STREAM_CHAT": ("shot-stream-chat.png", CF + "710/shot-stream-chat-png.png",
                          WAGO + "wlOCWtus9cDTdWpKuZGGc2ta1u0cjw2BB7Vi9QTM.png"),
    "IMAGE_SHIELD": ("05-shield.png", CF + "711/05-shield-png.png",
                     WAGO + "hpy8d3x6zsyHna4bCcFNst6iUJyiUIKHMvvkZe6v.png"),
    "IMAGE_CAMERA": ("06-camera.png", CF + "712/06-camera-png.png",
                     WAGO + "mxCgP0zhXtF02ulflO8UgJyM1U6sIHmkzxJXSqN1.png"),
    "IMAGE_LOOKS": ("07-looks.png", CF + "713/07-looks-png.png",
                    WAGO + "Ys36lPvZ3DOjDGhEuGjyPnCtSpUteYem1dUoO08s.png"),
    "IMAGE_DECK": ("08-deck.png", CF + "714/08-deck-png.png",
                   WAGO + "YUPV9zx8gthRji5ryZOt6YYQgDRChjrDA5wdTkrB.png"),
}


def main():
    with open(os.path.join(RELEASE, "description.md"), "rb") as f:
        text = f.read().decode("utf-8")
    for column, site in ((1, "curseforge"), (2, "wago")):
        page = re.sub(r"IMAGE_[A-Z_]+", lambda m: IMAGES[m.group(0)][column], text)
        path = os.path.join(RELEASE, f"description-{site}.md")
        with open(path, "wb") as f:
            f.write(page.encode("utf-8"))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
