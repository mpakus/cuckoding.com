# BOSS visual system

The application shares Cuckoding's paper, ink, sage and peach palette, thin
rules, small corner radii and Helvetica/Georgia typography. The application keeps
compact task controls and evidence panels; the public site's large artwork stays
in the marketing site.

`assets/css/app.css` owns semantic Tailwind colors and shared `app-*` components.
Use paper for the page, surface for panels, sage for quiet emphasis and peach for
setup. Danger and warning have separate text/background tokens. Controls have a
44 px minimum height, explicit borders and visible keyboard focus.

The root layout owns the BOSS identity, Projects/Agents navigation, skip link and
motion preference. Views own their page title, actions and content. Project boards
may scroll inside their labeled region; the document must fit at 320 px. Paths,
source and evidence must wrap or scroll within their own bounded container.

`assets/js/motion.mjs` owns a document-level preference. Motion starts disabled
until JavaScript initializes, respects live `prefers-reduced-motion`, and exposes
a persistent Pause motion checkbox. Keyboard input disables pointer transitions.
Buttons use 150 ms feedback; the native task drawer enters in 250 ms. No idle
loop, animated task progress, library dependency or delayed keyboard focus.

The native drawer hook, URL selection, form events and workflow evidence gates
are unchanged. The redesign does not authorize a task, a provider call or an
application restart.

Verification for the November 2 increment is recorded in
`.worklog/2026-11-02-editorial.md`. Static browser previews are rendered from real
LiveViews with isolated fixture data; they supplement, rather than replace,
connected LiveView tests. Live website publication is separate from local app
integration.
