"""Build docs/Phase2_Final_Report.pdf from docs/Phase2_Final_Report.md, with evidence screenshots embedded.

Usage (needs reportlab):  python3 scripts/build_report_pdf.py
The Markdown file stays the source of truth; re-run this after editing it.
"""
import re
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, ListFlowable, ListItem, PageBreak, Paragraph, Preformatted,
                                SimpleDocTemplate, Spacer, Table, TableStyle)
from reportlab.lib.fonts import addMapping

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/Phase2_Final_Report.md"
OUT = ROOT / "docs/Phase2_Final_Report.pdf"
EV = ROOT / "evidence"

# ---------- fonts (Arial Unicode covers → ✔ ≥ etc.) ----------
F = "/System/Library/Fonts/Supplemental/"
pdfmetrics.registerFont(TTFont("Body", F + "Arial Unicode.ttf"))
pdfmetrics.registerFont(TTFont("BodyB", F + "Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("BodyI", F + "Arial Italic.ttf") if Path(F + "Arial Italic.ttf").exists()
                        else TTFont("BodyI", F + "Arial Unicode.ttf"))
pdfmetrics.registerFont(TTFont("Mono", "/System/Library/Fonts/Menlo.ttc", subfontIndex=0))
addMapping("Body", 0, 0, "Body"); addMapping("Body", 1, 0, "BodyB")
addMapping("Body", 0, 1, "BodyI"); addMapping("Body", 1, 1, "BodyB")

NAVY = colors.HexColor("#1F3A5F"); TEAL = colors.HexColor("#1B7F8C"); GREY = colors.HexColor("#5A6270")
LIGHT = colors.HexColor("#EEF2F7"); CODEBG = colors.HexColor("#F4F5F7"); GREEN = colors.HexColor("#1E7B34")

S = {
    "body": ParagraphStyle("body", fontName="Body", fontSize=9.6, leading=13.2, spaceAfter=4),
    "h1": ParagraphStyle("h1", fontName="BodyB", fontSize=15, leading=19, textColor=NAVY, spaceBefore=10, spaceAfter=6, keepWithNext=1),
    "h2": ParagraphStyle("h2", fontName="BodyB", fontSize=11.5, leading=15, textColor=TEAL, spaceBefore=6, spaceAfter=4, keepWithNext=1),
    "note": ParagraphStyle("note", fontName="Body", fontSize=9, leading=12.5, textColor=GREY, leftIndent=8,
                           borderPadding=(4, 6, 4, 6), backColor=LIGHT, spaceAfter=8, spaceBefore=2),
    "cell": ParagraphStyle("cell", fontName="Body", fontSize=8.2, leading=10.6),
    "cellh": ParagraphStyle("cellh", fontName="BodyB", fontSize=8.2, leading=10.6, textColor=colors.white),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=7.4, leading=9.6, backColor=CODEBG,
                           borderPadding=(4, 4, 4, 4), spaceBefore=2, spaceAfter=8),
    "cap": ParagraphStyle("cap", fontName="BodyI", fontSize=8, leading=10, textColor=GREY, alignment=TA_CENTER,
                          spaceBefore=2, spaceAfter=10),
    "title": ParagraphStyle("title", fontName="BodyB", fontSize=24, leading=30, textColor=NAVY, alignment=TA_CENTER),
    "sub": ParagraphStyle("sub", fontName="Body", fontSize=12.5, leading=17, textColor=TEAL, alignment=TA_CENTER),
    "center": ParagraphStyle("center", fontName="Body", fontSize=10, leading=14, alignment=TA_CENTER, textColor=GREY),
}

# ---------- screenshots placed at the end of each section ----------
P1, P2 = "phase1", "phase2"
FIGS = {
    "4.": [(f"{P2}/A_backup_dns/A2_A3_primary_stopped_backup_answers.png",
            "A2/A3 — primary DNS on Mac 1 stopped; the client still resolves via the backup on Mac 3 and HTTPS returns 200; primary restored."),
           (f"{P2}/A_backup_dns/A1_backup_dns_records_both_servers.png",
            "A1 — primary (Mac 1) and backup (Mac 3) return identical records with TTL 30.")],
    "5.": [(f"{P2}/B_dns_ttl/B1_ttl_30_seconds.png", "B1 — first lookup TTL 30, then 26 / 22: answer served from the client cache."),
           (f"{P2}/B_dns_ttl/B3_old_cached_answer.png",
            "B3 — record changed on the server, but the client keeps the OLD cached IP until the TTL reaches 0, then gets the new IP."),
           (f"{P2}/B_dns_ttl/B5_manual_cache_flush.png", "B5 — stale cached answer, then a manual flush makes the change visible immediately.")],
    "6.": [(f"{P2}/C_firewall/C1_pf_firewall_rules.png", "C1 — PF rules in anchor com.apple/250.CNProject (output relayed from Mac 3)."),
           (f"{P2}/C_firewall/C2_C3_C4_edge_allowed_client_blocked_https_ok.png",
            "C2–C4 — PF on 23:13:27–23:14:57: Mac 1 → backend BLOCKED; Mac 2 edge still fetches from both backends (MISS, A/B); HTTPS 200."),
           (f"{P2}/C_firewall/C5_pf_rollback_to_baseline.png", "C5 — rollback: anchor flushed, PF disabled, rules equal to the saved baseline (relayed from Mac 3).")],
    "7.": [(f"{P2}/D_backend_failover/D1_D2_backend_A_stopped_B_serving.png",
            "D1/D2 — Backend A stopped at 23:12:38: every request through the Mac 2 edge is served by Backend B, HTTP 200."),
           (f"{P1}/07_failure_demos/Fail3_Fail4_one_then_both_backends_stopped.png",
            "Run 1 (standby edge) — A stopped → only B; both stopped → 502 Bad Gateway; restarted → A/B.")],
    "8.": [(f"{P2}/E_edge_migration/E2_dns_record_migrated.png", "E2 — app.team1.test migrated to the standby edge on both DNS servers."),
           (f"{P2}/E_edge_migration/E4_old_client_cached_dns.png",
            "E4 — after the cutover the existing (cached) client keeps reaching Mac 2 for 26 s while new clients reach Mac 3."),
           (f"{P2}/E_edge_migration/E5_new_client_resolves_standby.png", "E5 — TTL expired: all clients on the standby edge; only two real DNS lookups.")],
    "9.": [(f"{P2}/F_troubleshooting/F4_final_state_all_layers_pass.png",
            "F4 — diagnose.sh final state: every layer passes, both DNS servers consistent, both edges serving.")],
    "10.": [(f"{P1}/02_dns/TaskB_mac1_client_resolves_via_team_dns.png", "Task B/E — Mac 1 resolves through the team DNS; HTTPS by name, certificate verified."),
            (f"{P1}/06_http_caching/TaskF_cache_miss_hit_304.png", "Task F — Mac 2 edge cache: MISS → HIT → conditional request → 304 Not Modified."),
            (f"{P1}/03_tcp_tls_packet_capture/TaskG_tcp_handshake_tls_handshake.png",
             "Task G — saved capture: SYN / SYN-ACK / ACK, TLS 1.3 ClientHello / ServerHello, encrypted Application Data."),
            (f"{P1}/04_load_balancing/TaskD_load_balancing_round_robin.png", "Task D — round-robin load balancing A, B, A, B."),
            (f"{P1}/07_failure_demos/Fail1_wrong_dns_server.png", "Failure 1 — wrong DNS server: NXDOMAIN while the IP layer still works."),
            (f"{P1}/07_failure_demos/Fail2_dns_record_wrong_ip.png", "Failure 2 — DNS record points to a wrong IP: lookup succeeds, connection fails."),
            (f"{P1}/07_failure_demos/Fail5_wrong_destination_port.png", "Failure 5 — wrong destination port: TCP refused, correct port 200.")],
}

FRAME_W = A4[0] - 3.2 * cm
MAX_IMG_H = 12.5 * cm


def inline(t: str) -> str:
    t = t.replace("✅", "✔").replace("⏳", "…").replace("⚠️", "!").replace("⚠", "!")
    t = t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    codes = []

    def keep(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"
    t = re.sub(r"`([^`]+)`", keep, t)                      # protect code spans from bold/italic rules
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"(?<![\w*])\*(?![\s*])([^*]+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", t)
    t = re.sub(r"\x00(\d+)\x00", lambda m: f'<font name="Mono" size="8.2" color="#8A2D3B">{codes[int(m.group(1))]}</font>', t)
    return t


def heading_text(t: str) -> str:
    return inline(t.replace("✅", "").replace("⏳", "").strip())


CACHE = Path("/tmp") / "cn_report_img_cache"


def small(p: Path) -> Path:
    """Downscale to 1600 px wide and store as high-quality JPEG (embedded as-is by reportlab -> small PDF)."""
    from PIL import Image as PILImage
    CACHE.mkdir(exist_ok=True)
    out = CACHE / (p.parent.name + "__" + p.stem + ".jpg")
    if not out.exists() or out.stat().st_mtime < p.stat().st_mtime:
        im = PILImage.open(p).convert("RGB")
        if im.width > 1600:
            im = im.resize((1600, round(im.height * 1600 / im.width)), PILImage.LANCZOS)
        im.save(out, "JPEG", quality=90, subsampling=0, optimize=True)
    return out


def fig(rel: str, caption: str):
    p = EV / rel
    if not p.exists():
        return [Paragraph(f"[missing evidence file: {rel}]", S["cap"])]
    img = Image(str(small(p)))
    w, h = img.imageWidth, img.imageHeight
    scale = min(FRAME_W / w, MAX_IMG_H / h)
    img.drawWidth, img.drawHeight = w * scale, h * scale
    return [KeepTogether([img, Paragraph(f"{inline(caption)}<br/><font name='Mono' size='6.8'>evidence/{rel}</font>", S["cap"])])]


def topology():
    d = Drawing(FRAME_W, 205)
    boxes = [("Mac 1 — Manpreet", "10.7.9.246", ["Primary DNS (dnsmasq :53)", "Test client"], 0),
             ("Mac 2 — Avneet", "10.7.19.93", ["Main edge: nginx", "HTTPS :8443, HTTP :8080→301", "TLS · round robin · cache"], 1),
             ("Mac 3 — Riya", "10.7.31.224", ["Backend A :3001 · B :3002", "Backup DNS :53", "Standby edge nginx :8443"], 2)]
    bw, bh, gap = 132, 92, (FRAME_W - 3 * 132) / 2
    d.add(Rect(0, 150, FRAME_W, 26, fillColor=LIGHT, strokeColor=NAVY, strokeWidth=0.8, rx=4, ry=4))
    d.add(String(FRAME_W / 2, 159, "Private LAN 10.7.0.0/19 · gateway 10.7.0.1 · Wi-Fi en0", fontName="BodyB",
                 fontSize=9, fillColor=NAVY, textAnchor="middle"))
    xs = []
    for title, ip, lines, i in boxes:
        x = i * (bw + gap); xs.append(x)
        d.add(Line(x + bw / 2, 150, x + bw / 2, 140, strokeColor=NAVY, strokeWidth=1))
        d.add(Rect(x, 48, bw, bh, fillColor=colors.white, strokeColor=TEAL, strokeWidth=1.2, rx=5, ry=5))
        d.add(String(x + bw / 2, 124, title, fontName="BodyB", fontSize=9.5, fillColor=NAVY, textAnchor="middle"))
        d.add(String(x + bw / 2, 111, ip, fontName="Mono", fontSize=8.5, fillColor=TEAL, textAnchor="middle"))
        for k, ln in enumerate(lines):
            d.add(String(x + bw / 2, 94 - k * 12, ln, fontName="Body", fontSize=7.8, fillColor=colors.black, textAnchor="middle"))

    def arrow(x1, x2, y, label):
        d.add(Line(x1, y, x2, y, strokeColor=GREY, strokeWidth=1))
        s = 1 if x2 > x1 else -1
        d.add(Polygon([x2, y, x2 - 6 * s, y + 3, x2 - 6 * s, y - 3], fillColor=GREY, strokeColor=GREY))
        for k, part in enumerate(label.split("\n")):
            d.add(String((x1 + x2) / 2, y + 14 - k * 9, part, fontName="Body", fontSize=6.8, fillColor=GREY, textAnchor="middle"))
    arrow(xs[0] + bw, xs[1], 66, "HTTPS\n:8443")
    arrow(xs[1] + bw, xs[2], 66, "HTTP\n:3001/:3002")
    d.add(Line(xs[0] + bw / 2, 48, xs[0] + bw / 2, 22, strokeColor=GREY))
    d.add(Line(xs[0] + bw / 2, 22, xs[2] + bw / 2, 22, strokeColor=GREY))
    d.add(Polygon([xs[2] + bw / 2, 48, xs[2] + bw / 2 - 3, 42, xs[2] + bw / 2 + 3, 42], fillColor=GREY, strokeColor=GREY))
    d.add(Line(xs[2] + bw / 2, 22, xs[2] + bw / 2, 42, strokeColor=GREY))
    d.add(String((xs[0] + xs[2] + bw) / 2, 10, "DNS failover (UDP 53) and HTTPS to the standby edge after migration (Ext A / E)",
                 fontName="Body", fontSize=7, fillColor=GREY, textAnchor="middle"))
    return [d, Paragraph("Figure 1 — Three-Mac topology and roles (full diagrams: docs/Architecture.md).", S["cap"])]


def table(rows):
    data = [[Paragraph(inline(c).replace('color="#8A2D3B"', 'color="#FFFFFF"') if r == 0 else inline(c),
                       S["cellh"] if r == 0 else S["cell"]) for c in row] for r, row in enumerate(rows)]
    ncol = max(len(r) for r in rows)
    for row in data:
        row += [""] * (ncol - len(row))
    def clen(r, c):
        return len(re.sub(r"[`*]", "", rows[r][c])) if c < len(rows[r]) else 0
    weights = []
    for c in range(ncol):
        avg = sum(clen(r, c) for r in range(len(rows))) / len(rows)
        weights.append(max(avg, 0.6 * max(clen(r, c) for r in range(len(rows))) ** 0.75, len(rows[0][c]) if c < len(rows[0]) else 4, 6) ** 0.85)
    def longest_word(c):
        words = [w for r in range(len(rows)) if c < len(rows[r]) for w in re.sub(r"[`*]", "", rows[r][c]).split()]
        return max([len(w) for w in words] + [3])
    mins = [min(longest_word(c), 24) * 5.0 + 10 for c in range(ncol)]
    spare = FRAME_W - sum(mins)
    if spare > 0:
        widths = [m + spare * w / sum(weights) for m, w in zip(mins, weights)]
    else:
        widths = [FRAME_W * w / sum(weights) for w in weights]
    t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY), ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT]),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#C9D1DC")),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]))
    return [t, Spacer(1, 7)]


def split_row(line):
    cells = re.split(r"(?<!\\)\|", line.strip().strip("|"))
    return [c.strip().replace("\\|", "|") for c in cells]


def parse(md: str):
    story, section = [], None
    lines = md.splitlines()
    i = 0
    para, bullets = [], []

    def flush():
        nonlocal para, bullets
        if para:
            story.append(Paragraph(inline(" ".join(para)), S["body"])); para = []
        if bullets:
            story.append(ListFlowable([ListItem(Paragraph(inline(b), S["body"]), leftIndent=12, value="•") for b in bullets],
                                      bulletType="bullet", start="•", leftIndent=12, bulletFontName="Body"))
            bullets = []

    def end_section():
        if section and section in FIGS:
            for rel, cap in FIGS[section]:
                story.extend(fig(rel, cap))

    while i < len(lines):
        ln = lines[i]
        if ln.startswith("# ") or ln.startswith("**Computer Networks") or ln.startswith("Manpreet Singh (Mac 1)"):
            i += 1; continue                                     # covered by the title page
        if ln.startswith("## "):
            flush(); end_section()
            section = ln[3:].split()[0]
            story.append(Paragraph(heading_text(ln[3:]), S["h1"]))
            i += 1; continue
        if ln.startswith("### "):
            flush(); story.append(Paragraph(heading_text(ln[4:]), S["h2"])); i += 1; continue
        if ln.startswith("```"):
            flush(); j = i + 1; buf = []
            while j < len(lines) and not lines[j].startswith("```"):
                buf.append(lines[j]); j += 1
            story.append(Preformatted("\n".join(buf), S["code"], maxLineLength=118, newLineChars=""))
            i = j + 1; continue
        if ln.startswith("|"):
            flush(); rows = []
            while i < len(lines) and lines[i].startswith("|"):
                if not re.match(r"^\|\s*:?-{2,}", lines[i]):
                    rows.append(split_row(lines[i]))
                i += 1
            story.extend(table(rows))
            if section == "2." and rows and rows[0][0] == "Machine":
                story.extend(topology())
            continue
        if ln.startswith("> "):
            flush(); quote = []
            while i < len(lines) and lines[i].startswith(">"):
                quote.append(lines[i].lstrip("> ").strip()); i += 1
            story.append(Paragraph(inline(" ".join(quote)), S["note"])); continue
        if re.match(r"^\s*[-*] ", ln):
            if para:
                flush()
            text = re.sub(r"^\s*[-*] ", "", ln)
            while i + 1 < len(lines) and lines[i + 1].startswith("  ") and not re.match(r"^\s*[-*] ", lines[i + 1]):
                i += 1; text += " " + lines[i].strip()
            bullets.append(text); i += 1; continue
        if ln.strip() in ("---", ""):
            flush(); i += 1; continue
        if bullets or (para and re.match(r"^\*\*[A-Z][^*]{0,40}[.:)]\*\*", ln)):
            flush()                                              # "**Objective.**" etc. start a new paragraph
        para.append(ln.strip()); i += 1
    flush(); end_section()
    return story


def title_page():
    team = [["Member", "Machine", "IP", "Role"],
            ["Manpreet Singh", "Mac 1 — MacBook Pro", "10.7.9.246", "Primary DNS, test client"],
            ["Avneet Singh", "Mac 2 — MacBook Air", "10.7.19.93", "Main nginx edge (TLS, LB, cache)"],
            ["Riya Yadav", "Mac 3 — MacBook Pro", "10.7.31.224", "Backends A/B, backup DNS, standby edge"]]
    return [Spacer(1, 4.2 * cm),
            Paragraph("Private Network Service Platform", S["title"]), Spacer(1, 8),
            Paragraph("Phase 2 Final Report — Harden, Recover and Troubleshoot", S["sub"]), Spacer(1, 4),
            Paragraph("Computer Networks Course Project · Team Error-101 · <font name='Mono'>team1.test</font>", S["center"]),
            Spacer(1, 1.4 * cm), *table(team), Spacer(1, 1.0 * cm),
            Paragraph("Evidence collected 23 November 2026 on the team's private LAN (10.7.0.0/19).", S["center"]),
            Paragraph("Every result in this report is backed by a screenshot, log or packet capture in the project repository "
                      "(<font name='Mono'>evidence/</font>). Screenshots are reproduced inline; file paths are given under each figure.",
                      S["center"]),
            PageBreak()]


def on_page(c, doc):
    if doc.page == 1:
        return
    c.saveState()
    c.setFont("Body", 7.5); c.setFillColor(GREY)
    c.drawString(1.6 * cm, 1.0 * cm, "Private Network Service Platform — Phase 2 Final Report · Team Error-101")
    c.drawRightString(A4[0] - 1.6 * cm, 1.0 * cm, f"Page {doc.page}")
    c.setStrokeColor(colors.HexColor("#C9D1DC")); c.line(1.6 * cm, 1.35 * cm, A4[0] - 1.6 * cm, 1.35 * cm)
    c.restoreState()


def main():
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=1.6 * cm, rightMargin=1.6 * cm, topMargin=1.5 * cm,
                            bottomMargin=1.8 * cm, title="Private Network Service Platform — Phase 2 Final Report",
                            author="Team Error-101: Manpreet Singh, Avneet Singh, Riya Yadav", subject="Computer Networks course project")
    doc.build(title_page() + parse(SRC.read_text()), onFirstPage=on_page, onLaterPages=on_page)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
