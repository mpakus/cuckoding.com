# frozen_string_literal: true

root = File.expand_path(__dir__)
html = File.read(File.join(root, "index.html"))
css = File.read(File.join(root, "styles.css"))
javascript = File.read(File.join(root, "script.js"))
workflow = File.read(File.join(root, "../.github/workflows/pages.yml"))

def assert(condition, message)
  raise message unless condition
end

local_refs = html.scan(/\b(?:href|src)="([^"]+)"/).flatten.reject do |ref|
  ref.start_with?("#", "http://", "https://")
end

missing = local_refs.reject { |ref| File.file?(File.join(root, ref.split(/[?#]/, 2).first)) }
assert(missing.empty?, "missing local references: #{missing.join(", ")}")
assert(html.scan(/<h1\b/).length == 1, "expected exactly one h1")
images = html.scan(/<img\b[^>]*>/m)
assert(images.all? { |tag| tag.match?(/\balt="[^"]*"/) }, "every image needs alt text")
assert(images.all? { |tag| tag.match?(/\bwidth="\d+"/) && tag.match?(/\bheight="\d+"/) }, "every image needs intrinsic dimensions")
assert(html.include?('href="#main"') && html.match?(/<main\b[^>]*\bid="main"/), "skip link must target main")
assert(html.include?('src="assets/pic1.webp"'), "new primary image must lead the page")
assert(html.scan('src="assets/icon.webp"').length == 3, "new logo must appear in the header, hero, and footer")
%w[pic1 pic2 pic3 pic4 square].each do |name|
  assert(html.include?("assets/#{name}.webp"), "missing new #{name} artwork")
end
(1..6).each do |number|
  assert(html.include?("assets/person#{number}.webp"), "missing layered person#{number} artwork")
end
assert(
  html.include?("Project → Repository → Review") &&
    html.include?("Project settings → Agents → Roles"),
  "new project and agent flow must stay public"
)
assert(
  html.include?("Available now") &&
    html.include?("Next in beta") &&
    html.include?("Foundation live"),
  "current and planned capabilities must be distinguished"
)
assert(html.include?("trusted-host") && html.include?("not a container or sandbox"), "host-runner limitation must stay public")
assert(html.include?("setup-only") && html.include?("never autonomously merges or deploys"), "runtime and automation limits must stay public")
assert(css.include?("prefers-reduced-motion: reduce"), "reduced motion support is required")
assert(css.match?(/\.hero-stage img,[^{]+\{[^}]*object-fit:\s*contain/m), "primary artwork must preserve its proportions")
assert(css.match?(/\.crew-member img\s*\{[^}]*object-fit:\s*contain/m), "character artwork must preserve its proportions")
assert(!css.match?(/transition\s*:\s*all\b/), "transition: all is not allowed")
assert(javascript.include?("IntersectionObserver") && javascript.include?("requestAnimationFrame"), "scroll behavior must use native browser APIs")
uses = workflow.lines.grep(/^\s*(?:-\s*)?uses:/)
assert(uses.length == 4 && uses.all? { |line| line.match?(/@[0-9a-f]{40}\b/) }, "all four workflow actions must be pinned")
assert(File.read(File.join(root, "CNAME")).strip == "cuckoding.com", "custom domain mismatch")

puts "GitHub Pages site verified: #{local_refs.uniq.length} local references, #{uses.length} pinned actions"
