# SPDX-License-Identifier: MIT
import importlib.util
import pathlib
import types
import unittest
import sys
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("downloader", pathlib.Path(__file__).parents[2] / "macos/Resources/instagram-download.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SelectionTests(unittest.TestCase):
    def test_mixed_carousel_uses_original_slide_position_and_video_bytes(self):
        nodes = [types.SimpleNamespace(is_video=False, display_url="https://example.com/first.jpg", video_url=None),
                 types.SimpleNamespace(is_video=True, display_url="https://example.com/poster.jpg", video_url="https://example.com/second.mp4"),
                 types.SimpleNamespace(is_video=False, display_url="https://example.com/third.jpg", video_url=None)]
        post = types.SimpleNamespace(typename="GraphSidecar", get_sidecar_nodes=lambda start, end: iter(nodes[start:end+1]))
        self.assertEqual(module.selected_media(post, 1), (False, nodes[0].display_url))
        self.assertEqual(module.selected_media(post, 2), (True, nodes[1].video_url))
        self.assertEqual(module.selected_media(post, 3), (False, nodes[2].display_url))
        with self.assertRaises(ValueError): module.selected_media(post, 4)

    def test_single_reel_rejects_nonexistent_slide(self):
        post = types.SimpleNamespace(typename="GraphVideo", is_video=True, video_url="https://example.com/reel.mp4")
        self.assertEqual(module.selected_media(post, 1), (True, post.video_url))
        with self.assertRaises(ValueError): module.selected_media(post, 2)

if __name__ == "__main__": unittest.main()
