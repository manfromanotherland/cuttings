# SPDX-License-Identifier: GPL-3.0-or-later
"""Instaloader transport only: receive a validated shortcode/index, emit one file.
No sessions, account credentials, source metadata, or library writes live here.
"""
import pathlib
import sys
from urllib.parse import urlsplit
import instaloader


def selected_media(post, slide):
    if post.typename == "GraphSidecar":
        nodes = list(post.get_sidecar_nodes(start=slide - 1, end=slide - 1))
        if len(nodes) != 1:
            raise ValueError("Selected carousel slide does not exist")
        node = nodes[0]
        return node.is_video, node.video_url if node.is_video else node.display_url
    if slide != 1:
        raise ValueError("Selected slide does not exist")
    return post.is_video, post.video_url if post.is_video else post.url


def download(shortcode, slide, directory):
    loader = instaloader.Instaloader(quiet=True, max_connection_attempts=1,
                                    request_timeout=25, iphone_support=False)
    try:
        post = instaloader.Post.from_shortcode(loader.context, shortcode)
        video, url = selected_media(post, slide)
        if not url or urlsplit(url).scheme != "https":
            raise ValueError("Selected media has no HTTPS download")
        limit = 1024 ** 3 if video else 40 * 1024 ** 2
        target = pathlib.Path(directory) / ("payload.mp4" if video else "payload.jpg")
        with loader.context.get_raw(url) as response, target.open("xb") as output:
            size = 0
            for chunk in response.iter_content(chunk_size=256 * 1024):
                size += len(chunk)
                if size > limit:
                    raise ValueError("Selected media exceeds capture limit")
                output.write(chunk)
            if not size:
                raise ValueError("Empty media response")
    finally:
        loader.close()


if __name__ == "__main__":
    try:
        download(sys.argv[1], int(sys.argv[2]), sys.argv[3])
    except Exception:
        # No signed CDN URLs, response bodies or cookies in diagnostics.
        print("Instagram media download failed", file=sys.stderr)
        sys.exit(1)
