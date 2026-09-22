# Instagram selected-media download

Research date: 2026-09-22. Source review plus the live checks recorded below; iOS Shortcut integration remains unverified.

## Live result and recommendation

Instaloader 4.15.3 successfully downloaded slide 2 of the supplied post without credentials, producing `/tmp/oia-instaloader-slide2/2026-09-22_10-45-41_UTC_2.jpg`. The parent task ran:

```sh
instaloader --no-captions --no-metadata-json --no-video-thumbnails \
  --slide 2 --max-connection-attempts 1 --request-timeout 20 \
  --dirname-pattern /tmp/oia-instaloader-slide2 -- -DdlVpikk5Gj
```

A second run with `--slide 1` also succeeded. Both runs produced exactly one JPEG, with different SHA-256 hashes; slide 2 is a 720 × 901 aerial photograph of the island. The verified slide-2 download is available at `/Users/ed/.codex/visualizations/2026/09/22/01a0c904-8298-7510-bbe9-e4ba5d129ab2/instagram/slide-2.jpg`.

A temporary installation of the latest gallery-dl, tested with `--range 2 --retries 0 -o timeout=20`, redirected to login instead. Prefer **Instaloader for the local Mac helper** on this evidence. This proves retrieval of a selected photo for this post and network, not permanent anonymous availability, video behavior, or a pure iPhone Shortcut implementation.

The supplied share URLs identify the same post (`DdlVpikk5Gj`), with `img_index=2` in the second-slide URL. A capture adapter must preserve that selection and explicitly select the corresponding media item. Treat a missing index as the first item for this observed sharing pattern; reject malformed or out-of-range indices instead of silently saving another slide. Remove the `stkn` share token from persisted origin metadata.

## Candidate comparison

| Tool | Selected carousel media | Fit |
| --- | --- | --- |
| gallery-dl | Downloads images and videos; `--range 2` limits a single-post extraction to its second file. Instagram files default to display order. | Candidate covering both formats, but the live check redirected to login. Explicitly disable previews and use ascending order so file positions correspond to slides. |
| Instaloader | `--slide 2` selects a sidecar item. Its Python API exposes sidecar nodes and per-node media information. | Recommended from the successful live photo download, with a direct selection interface. Python runtime and session handling still need integration. |
| yt-dlp | Instagram node extraction skips non-video nodes. | Useful for video downloading, including as gallery-dl's DASH backend, but unsuitable as the sole photo/carousel extractor. A video playlist position must not be confused with the original mixed carousel position. |

Sources: [gallery-dl command options](https://gdl-org.github.io/docs/options.html), [Instagram configuration](https://gdl-org.github.io/docs/configuration.html#extractor-instagram-order-files), [Instaloader slide option](https://instaloader.github.io/cli-options.html#cmdoption-slide), [Instaloader structures](https://instaloader.github.io/module/structures.html#instaloader.Post.get_sidecar_nodes), [yt-dlp Instagram source](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/instagram.py).

## gallery-dl details

Its post extractor reads the shortcode and asks its Instagram API adapter for the post. The reviewed implementation contains no `img_index` handling: passing the shared URL alone does not select the slide. The caller must parse the index. [Extractor source](https://github.com/mikf/gallery-dl/blob/master/gallery_dl/extractor/instagram.py)

Configuration exposes `previews=false` (the default) and `videos="merged"` for premerged video formats. The default video mode uses DASH data through yt-dlp. These are distinct choices: premerged media simplifies deployment; DASH may require additional processing. Source metadata and downloaded bytes should be validated before submitting one image/video capture to the existing Rust import path. [Video configuration](https://gdl-org.github.io/docs/configuration.html#extractor-instagram-videos)

## Integration and limitations

These are Python tools, not native Shortcuts actions. A Mac helper can run them locally; an iPhone-only Shortcut would require an additional runtime/app or a separate implementation. A Mac-mediated path would also require the Mac to be reachable or defer capture until it processes a request. This is an architectural consequence, not a verified end-to-end iOS solution. [gallery-dl installation](https://github.com/mikf/gallery-dl#installation), [Instaloader installation](https://instaloader.github.io/installation.html)

None establishes guaranteed anonymous retrieval from Instagram. Instaloader documents rate limits, authentication challenges, and session reuse. A framework can maintain extraction compatibility but cannot guarantee that Instagram serves a given post from a given device/network without authentication. Credentials, when explicitly configured, should remain on the capture device, outside the synced library. [Instaloader troubleshooting](https://instaloader.github.io/troubleshooting.html)

Acceptance requires a real download of the supplied first and second slide, distinct verified media identities, exactly one local asset per capture, correct original slide selection in mixed image/video posts, and a clear failure when media is unavailable. A preview image, link card, zero-file successful exit, or successful metadata extraction alone is not sufficient evidence.
