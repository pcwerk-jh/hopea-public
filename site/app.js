// Hopea Looks site. Reads catalog.json and renders pages with DOM APIs only:
// community text is always inserted as text, never as HTML.

const REPO = "https://github.com/rovetravel/hopea-public";
const SUBMIT_URL = `${REPO}/issues/new?template=submit-look.yml`;

async function loadCatalog() {
  const response = await fetch("catalog.json", { cache: "no-cache" });
  if (!response.ok) throw new Error(`catalog.json: HTTP ${response.status}`);
  return response.json();
}

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key === "text") node.textContent = value;
    else node.setAttribute(key, value);
  }
  for (const child of children) if (child) node.append(child);
  return node;
}

function lookURL(look) {
  return `look.html?id=${encodeURIComponent(look.id)}`;
}

function safeHTTPS(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" ? parsed.href : null;
  } catch {
    return null;
  }
}

// MARK: Index

async function renderIndex() {
  const grid = document.getElementById("grid");
  const tagBar = document.getElementById("tags");
  document.getElementById("submit").href = SUBMIT_URL;
  let catalog;
  try {
    catalog = await loadCatalog();
  } catch (error) {
    grid.replaceChildren(el("p", { class: "error", text: `Couldn't load looks (${error.message}).` }));
    return;
  }

  const tags = [...new Set(catalog.looks.flatMap((look) => look.tags))].sort();
  let active = new URLSearchParams(location.search).get("tag");

  function draw() {
    const looks = catalog.looks.filter((look) => !active || look.tags.includes(active));
    grid.replaceChildren(
      ...looks.map((look) =>
        el("a", { class: "card", href: lookURL(look) },
          el("img", { src: look.previews[0] || "", alt: `${look.name} preview`, loading: "lazy" }),
          el("div", { class: "meta" },
            el("div", { class: "name", text: look.name }),
            el("div", { class: "by", text: `by @${look.author.handle}` })))));
    if (!looks.length) grid.append(el("p", { class: "empty", text: "No looks with that tag yet." }));
    tagBar.replaceChildren(
      ...[null, ...tags].map((tag) => {
        const chip = el("button", { class: `tag${tag === active ? " active" : ""}`, text: tag ?? "all" });
        chip.addEventListener("click", () => { active = tag; draw(); });
        return chip;
      }));
  }
  draw();
}

// MARK: Look page

async function renderLook() {
  const root = document.getElementById("look");
  const id = new URLSearchParams(location.search).get("id");
  let catalog;
  try {
    catalog = await loadCatalog();
  } catch (error) {
    root.replaceChildren(el("p", { class: "error", text: `Couldn't load looks (${error.message}).` }));
    return;
  }
  const look = catalog.looks.find((item) => item.id === id);
  if (!look) {
    root.replaceChildren(el("p", { class: "error", text: "That look isn't in the catalog." }));
    return;
  }
  document.title = `${look.name} — Hopea Looks`;

  const author = safeHTTPS(look.author.url)
    ? el("a", { href: safeHTTPS(look.author.url), rel: "noopener nofollow", text: look.author.name })
    : document.createTextNode(look.author.name);
  const licenseURL = look.license === "CC0-1.0"
    ? "https://creativecommons.org/publicdomain/zero/1.0/"
    : "https://creativecommons.org/licenses/by/4.0/";

  const rows = [
    ["Look id", el("code", { text: look.id })],
    ["Version", document.createTextNode(look.version)],
    ["Licence", el("a", { href: licenseURL, text: look.license })],
    look.remixOf ? ["Remix of", el("code", { text: look.remixOf })] : null,
    look.tags.length ? ["Tags", document.createTextNode(look.tags.join(", "))] : null,
    ["SHA-256", el("code", { text: look.sha256 })],
  ].filter(Boolean);

  root.replaceChildren(
    el("div", { class: "gallery" },
      ...look.previews.map((src) => el("img", { src, alt: `${look.name} on a reference photo`, loading: "lazy" }))),
    el("div", {},
      el("h1", { text: look.name }),
      el("p", { class: "by" }, document.createTextNode("by "), author, document.createTextNode(` · @${look.author.handle}`)),
      look.description ? el("p", { text: look.description }) : null,
      el("p", { class: "by", text: "Add it in the Hopea app: Settings → Looks → Get more looks." }),
      el("div", { class: "actions" },
        el("a", { class: "button secondary", href: look.package, download: "", text: "Download .hopealook" })),
      el("table", { class: "details" },
        el("tbody", {}, ...rows.map(([label, value]) => el("tr", {}, el("td", { text: label }), el("td", {}, value)))))));
}

if (document.getElementById("grid")) renderIndex();
if (document.getElementById("look")) renderLook();
