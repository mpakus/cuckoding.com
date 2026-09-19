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
assert(html.scan(/<h1\b/).length == 1, "expected exactly one h1")
images = html.scan(/<img\b[^>]*>/m)
assert(images.all? { |tag| tag.match?(/\balt="[^"]*"/) }, "every image needs alt text")
assert(images.all? { |tag| tag.match?(/\bwidth="\d+"/) && tag.match?(/\bheight="\d+"/) }, "every image needs intrinsic dimensions")
assert(html.include?('href="#main"') && html.match?(/<main\b[^>]*\bid="main"/), "skip link must target main")
assert(html.include?('href="assets/pic1.webp"'), "primary background must stay preloaded")
assert(html.scan('src="assets/icon.webp"').length == 3, "new logo must appear in the header, hero, and footer")
%w[pic1 pic2 pic3 pic4 square].each do |name|
  assert(css.include?("--scene-image: url(\"assets/#{name}.webp\")"), "missing #{name} scene background")
end
(1..6).each do |number|
  assert(
    html.match?(/class="(?:scene-agent|finale-agent)[^"]*" src="assets\/person#{number}\.webp"[^>]*data-parallax=/),
    "missing parallax person#{number} foreground"
  )
end
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
assert(html.include?("run-scoped") && html.include?("queued and active runs"), "current run and monitoring boundaries must stay public")
assert(html.include?("trusted-host") && html.include?("not a container or sandbox"), "host-runner limitation must stay public")
assert(html.include?("setup-only") && html.include?("never autonomously merges or deploys"), "runtime and automation limits must stay public")
assert(html.scan(/\bdata-parallax="[^"]+"/).length >= 10, "expected layered decorative parallax")
assert(css.include?("prefers-reduced-motion: reduce"), "reduced motion support is required")
assert(css.include?("--ease-out: cubic-bezier(0.23, 1, 0.32, 1)") && css.include?("[data-reveal=\"clip\"]"), "approved motion tokens and clip reveal are required")
assert(css.match?(/\.scene-agent\s*\{[^}]*object-fit:\s*contain/m), "parallax characters must preserve their proportions")
assert(!css.match?(/transition\s*:\s*all\b/), "transition: all is not allowed")
assert(
  html.include?('<section class="finale" aria-labelledby="finale-title">') &&
    html.scan('class="finale-agent ').length == 2 &&
    html.include?("Make the agents busy.<br>Keep the work legible."),
  "finale reference composition must stay intact"
)
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
