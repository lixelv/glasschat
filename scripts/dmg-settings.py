"""Finder layout for the drag-to-install GlassChat disk image."""

application = defines.get("app", "build/GlassChat.app")
files = [(application, "GlassChat.app")]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
volume_name = "GlassChat"
background = None
window_rect = ((200, 200), (600, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 112
text_size = 14
label_pos = "bottom"
icon_locations = {
    "GlassChat.app": (150, 160),
    "Applications": (450, 160),
}
hide_extensions = ["GlassChat.app"]
