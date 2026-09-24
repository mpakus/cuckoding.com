# frozen_string_literal: true

root = File.expand_path(__dir__)
html = File.read(File.join(root, "index.html"))
css = File.read(File.join(root, "styles.css"))
javascript = File.read(File.join(root, "script.js"))
workflow = File.read(File.join(root, "../.github/workflows/pages.yml"))

def assert(condition, message)
  raise message unless condition
end

html_refs = html.scan(/\b(?:href|src)="([^"]+)"/).flatten
css_refs = css.scan(/url\(["']?([^"')]+)["']?\)/).flatten
local_refs = (html_refs + css_refs).uniq.reject do |ref|
  ref.start_with?("#", "http://", "https://")
end

missing = local_refs.reject { |ref| File.file?(File.join(root, ref.split(/[?#]/, 2).first)) }
assert(missing.empty?, "missing local references: #{missing.join(", ")}")
ids = html.scan(/\bid="([^"]+)"/).flatten
assert(ids.uniq == ids, "duplicate HTML IDs")
anchors = html_refs.grep(/^#/).map { |ref| ref.delete_prefix("#") }
assert((anchors - ids).empty?, "every local anchor must have a target")
assert(html.scan(/<h1\b/).length == 1, "expected exactly one h1")
images = html.scan(/<img\b[^>]*>/m)
assert(images.all? { |tag| tag.match?(/\balt="[^"]*"/) }, "every image needs alt text")
assert(images.all? { |tag| tag.match?(/\bwidth="\d+"/) && tag.match?(/\bheight="\d+"/) }, "every image needs intrinsic dimensions")
assert(html.include?('href="#main"') && html.match?(/<main\b[^>]*\bid="main"/), "skip link must target main")
assert(html.include?('rel="preload" href="assets/irony-crew.webp"'), "hero artwork must be preloaded")
%w[pearl irony].each do |mode|
  artwork = %w[crew path knowledge].map { |scene| "#{mode}-#{scene}" }
  artwork.each do |name|
    assert(html.include?("src=\"assets/#{name}.webp\""), "missing #{name} illustration")
    bytes = File.binread(File.join(root, "assets/#{name}.webp"))
    assert(bytes[0, 4] == "RIFF" && bytes[8, 4] == "WEBP", "invalid WebP: #{name}")
  end
  assert(artwork.sum { |name| File.size(File.join(root, "assets/#{name}.webp")) } < 400_000, "#{mode} illustrations exceed the 400 KB budget")
end
assert(html.include?('<legend class="sr-only">Illustration mode</legend>'), "illustration radios need a group label")
assert(images.all? { |tag| tag.include?('data-classic-alt=') }, "every alternate image needs its corresponding text alternative")
assert(html.scan(/type="radio" name="illustration-mode"/).length == 2, "expected two native illustration choices")
assert(html.scan(/>Satirical artwork/).length == 3, "all irony scenes must identify their satire")
assert(html.include?('content="https://cuckoding.com/assets/irony-crew.webp"'), "social preview must use current artwork")
assert(html.scan(/concept artwork/i).length >= 3 && html.include?("Illustrative view · sample content"), "artwork and sample UI must be labeled")
assert(
  html.include?("Project → Repository → Review") &&
    html.include?("Project settings → Agents → Roles") &&
    html.include?("Board → Draft task → Ready") &&
    html.include?("Prepare run → Authenticate → Inspect"),
  "current project-to-run flow must stay public"
)
assert(
  html.scan("Available now").length >= 6 &&
    html.include?("External gates pending") &&
    html.include?("No public release yet"),
  "available features and external release gates must be distinguished"
)
assert(
  !html.include?("Next in beta") &&
    !html.include?("Illustrative planned Kanban") &&
    !html.include?("Default planned workflow"),
  "stale workflow labels found"
)
assert(html.downcase.include?("run-scoped") && html.include?("queued and active runs"), "current run and monitoring boundaries must stay public")
assert(html.include?("trusted-host") && html.include?("not a container or sandbox"), "host-runner limitation must stay public")
assert(html.include?("setup-only") && html.include?("never autonomously merges or deploys"), "runtime and automation limits must stay public")
assert(html.include?("Codex, Claude Code, and Cursor Agent are supported launch adapters."), "current supported adapters must stay accurate")
assert(html.include?("OpenCode and Custom Agent are setup-only."), "setup-only adapter boundary must stay explicit")
assert(html.include?("Task states and workflow stages are separate"), "illustrative board must distinguish states and stages")
assert(css.include?("color-scheme: light"), "pearl design uses the light color scheme")
assert(css.include?("prefers-reduced-motion: reduce"), "reduced motion support is required")
assert(css.include?("forced-colors: active") && css.include?(":focus-visible"), "high-contrast and keyboard focus support required")
assert(!html.match?(/<(?:p|h[1-6]|a)\b[^>]*data-(?:parallax|reveal)/), "readable copy and controls must remain stable")
assert(!css.match?(/transition\s*:\s*all\b/), "transition: all is not allowed")
assert(
  html.include?('<a class="origin-link" href="https://aomega.co">Made in Austin ☆ Texas.</a> Runs on your Mac. Humans remain accountable'),
  "Austin footer credit or destination mismatch"
)
assert(
  javascript.include?("IntersectionObserver") &&
    javascript.include?("requestAnimationFrame") &&
    javascript.include?('removeAttribute("style")'),
  "scroll behavior must use native browser APIs and clear parallax for reduced motion"
)
uses = workflow.lines.grep(/^\s*(?:-\s*)?uses:/)
assert(uses.length == 4 && uses.all? { |line| line.match?(/@[0-9a-f]{40}\b/) }, "all four workflow actions must be pinned")
assert(File.read(File.join(root, "CNAME")).strip == "cuckoding.com", "custom domain mismatch")

puts "GitHub Pages site verified: #{local_refs.uniq.length} local references, #{uses.length} pinned actions"
