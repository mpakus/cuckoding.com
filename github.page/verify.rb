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
assert(html.include?('src="assets/main.webp"'), "main image must lead the page")
assert(html.include?('class="hero-logo"') && html.include?('src="assets/logo.webp"'), "full logo must be prominent in the hero")
assert(html.scan('src="assets/brand-mark.webp"').length == 2, "brand mark must appear in the header and footer")
%w[bender fry leila prof].each do |name|
  assert(html.include?("assets/#{name}.webp"), "missing layered #{name} artwork")
end
assert(html.include?("trusted-host runner") && html.include?("not a container or sandbox"), "host-runner limitation must stay public")
assert(css.include?("prefers-reduced-motion: reduce"), "reduced motion support is required")
assert(css.match?(/\.art-frame img\s*\{[^}]*object-fit:\s*contain/m), "primary artwork must preserve its proportions")
assert(css.match?(/\.concept-strip img\s*\{[^}]*object-fit:\s*contain/m), "concept artwork must preserve its proportions")
assert(!css.match?(/transition\s*:\s*all\b/), "transition: all is not allowed")
assert(javascript.include?("IntersectionObserver") && javascript.include?("requestAnimationFrame"), "scroll behavior must use native browser APIs")
uses = workflow.lines.grep(/^\s*(?:-\s*)?uses:/)
assert(uses.length == 4 && uses.all? { |line| line.match?(/@[0-9a-f]{40}\b/) }, "all four workflow actions must be pinned")
assert(File.read(File.join(root, "CNAME")).strip == "cuckoding.com", "custom domain mismatch")

puts "GitHub Pages site verified: #{local_refs.uniq.length} local references, #{uses.length} pinned actions"
