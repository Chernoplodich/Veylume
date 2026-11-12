import os

app = os.path.abspath(defines['app'])
root = os.path.abspath(defines['root'])
format = 'UDZO'
filesystem = 'HFS+'
readme = 'Install-Readme-release.txt' if defines.get('distribution') == 'release' else 'Install-Readme.txt'
files = [app, (os.path.join(root, 'Configuration', readme), 'Read me.txt')]
symlinks = {'Applications': '/Applications'}
background = defines.get('background', os.path.join(root, 'Configuration/Artwork/DMG-background.png'))
icon = defines.get('icon', os.path.join(root, 'Configuration/AppIcon.icns'))
window_rect = ((120, 120), (600, 480))
icon_locations = {
    'Veylume.app': (160, 145),
    'Applications': (440, 145),
    'Read me.txt': (300, 340),
    # Finder's Show Hidden Files also reveals files marked invisible. Keep the
    # packaging resources outside the initial viewport in that mode as well.
    '.background.png': (1200, 100),
    '.VolumeIcon.icns': (1200, 100),
    '.DS_Store': (1200, 100),
    '.fseventsd': (1200, 100),
}
hide = ['.background.png', '.VolumeIcon.icns']
# Never SetFile a signed bundle: its FinderInfo would invalidate strict codesign.
# Finder already displays application bundles without the .app suffix normally.
hide_extensions = ['Read me.txt']
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
show_icon_preview = False
show_item_info = False
scroll_position = (0, 0)
text_size = 12
icon_size = 76
arrange_by = None
