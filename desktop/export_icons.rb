# frozen_string_literal: true

require "fileutils"
require "rexml/document"
require "tmpdir"

# Run after editing icon.svg. Exports are committed; app builds need no art tools.
root = File.expand_path("..", __dir__)
source = File.join(__dir__, "icon.svg")
icons = File.join(__dir__, "src-tauri/icons")
pages = File.join(root, "github.page")
web = File.join(root, "priv/static")

def run(*args)
  system("rtk", "proxy", *args, exception: true)
end

Dir.mktmpdir("cuckoding-icons-") do |tmp|
  master = File.join(icons, "icon.png")
  run("rsvg-convert", "-w", "1024", "-h", "1024", "-o", master, source)
  FileUtils.cp(master, File.join(root, "icon.png"))

  iconset = File.join(tmp, "Cuckoding.iconset")
  FileUtils.mkdir_p(iconset)
  [16, 32, 128, 256, 512].each do |size|
    [1, 2].each do |scale|
      name = "icon_#{size}x#{size}#{scale == 2 ? '@2x' : ''}.png"
      run("magick", master, "-resize", "#{size * scale}x#{size * scale}", "-strip",
          File.join(iconset, name))
    end
  end
  run("iconutil", "-c", "icns", iconset, "-o", File.join(icons, "icon.icns"))

  mark = REXML::Document.new(File.read(source)).elements["svg/g[@id='mark']"]
  raise "Missing master mark" unless mark

  mark.attributes["fill"] = "#000000"
  mark.attributes.delete("filter")
  tray_svg = File.join(tmp, "tray.svg")
  File.write(tray_svg, %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="70 55 340 370">#{mark}</svg>))
  tray_png = File.join(tmp, "tray.png")
  run("rsvg-convert", "-w", "64", "-h", "64", "-o", tray_png, tray_svg)
  run("magick", tray_png, "-channel", "RGB", "-evaluate", "set", "0", "+channel",
      "-depth", "8", "rgba:#{File.join(icons, 'tray-icon.rgba')}")

  FileUtils.cp(source, File.join(pages, "assets/brand-icon.svg"))
  FileUtils.cp(source, File.join(web, "assets/images/brand-icon.svg"))
  run("magick", master, "-resize", "256x256", "-strip", File.join(pages, "icon.png"))
  run("magick", master, "-resize", "256x256", "-strip", "-quality", "90", File.join(pages, "assets/icon.webp"))
  run("magick", master, "-strip", "-define", "icon:auto-resize=64,32,16", File.join(pages, "favicon.ico"))
  FileUtils.cp(File.join(pages, "favicon.ico"), File.join(web, "favicon.ico"))
end

puts "Exported matching web, app and monochrome tray icons from desktop/icon.svg"
