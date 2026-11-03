import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { PDFDocument, PDFFont, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";

// ── Types ─────────────────────────────────────────────────────────────────────

interface InvoiceItem {
  name: string;
  qty: string;
  unitPrice: string;
  totalPrice: string;
}

interface InvoiceAddon {
  name: string;
  price: string;
}

interface BookingData {
  invoiceNumber: string;
  invoiceDate: string;
  customerName: string;
  customerPhone: string;
  customerEmail: string;
  customerAddress: string;
  bookingRef: string;
  serviceDate: string;
  assignedTo: string;
  paymentMethod: string;
  items: InvoiceItem[];
  addons: InvoiceAddon[];
  subtotal: string;
  taxLabel: string;
  taxAmount: string;
  discount: string;
  grandTotal: string;
}

interface RequestBody {
  templatePath: string;
  booking: BookingData;
}

// ── Colours ───────────────────────────────────────────────────────────────────

const C_BLACK  = rgb(0.067, 0.067, 0.067);
const C_GRAY   = rgb(0.37,  0.39,  0.41);
const C_LGRAY  = rgb(0.56,  0.58,  0.60);
const C_WHITE  = rgb(1,     1,     1);
const C_DARK   = rgb(0.067, 0.067, 0.067);
const C_GOLD   = rgb(0.831, 0.686, 0.216);
const C_STRIPE = rgb(0.969, 0.969, 0.980);
const C_BORDER = rgb(0.898, 0.906, 0.922);

// ── Font loading ──────────────────────────────────────────────────────────────
// Complete (unsubsetted) Noto Sans TTF — covers Latin, Cyrillic, Greek, and all
// Currency Symbols including ₹ (U+20B9).  Served via jsDelivr CDN which mirrors
// the notofonts/noto-fonts GitHub repository.

const FONT_REGULAR_URL = "https://cdn.jsdelivr.net/gh/notofonts/noto-fonts@main/hinted/ttf/NotoSans/NotoSans-Regular.ttf";
const FONT_BOLD_URL    = "https://cdn.jsdelivr.net/gh/notofonts/noto-fonts@main/hinted/ttf/NotoSans/NotoSans-Bold.ttf";

// Module-level cache: re-used across warm invocations of the same function instance.
let _fontCache: { regular: Uint8Array; bold: Uint8Array } | null = null;

async function loadFonts(): Promise<{ regular: Uint8Array; bold: Uint8Array }> {
  if (_fontCache) return _fontCache;

  const fetchFont = async (url: string, label: string): Promise<Uint8Array> => {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`Font fetch failed [${r.status}] ${label}: ${url}`);
    return new Uint8Array(await r.arrayBuffer());
  };

  const [regular, bold] = await Promise.all([
    fetchFont(FONT_REGULAR_URL, "NotoSans-Regular"),
    fetchFont(FONT_BOLD_URL,    "NotoSans-Bold"),
  ]);

  _fontCache = { regular, bold };
  console.log(`[invoice-fill] Fonts loaded — regular ${regular.byteLength}B, bold ${bold.byteLength}B`);
  return _fontCache;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Safe base64 encoding for large Uint8Arrays.
// The spread-operator approach `btoa(String.fromCharCode(...bytes))` overflows
// the V8 call-stack for arrays > ~65 KB, so we chunk instead.
function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = "";
  const CHUNK = 0x8000; // 32 KB
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    },
  });
}

// ── Entry point ───────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { templatePath, booking } = body;
  if (!templatePath || !booking) {
    return json({ error: "templatePath and booking are required" }, 400);
  }

  // Download template PDF from storage
  const { data: blob, error: storageErr } = await supabase.storage
    .from("cms-media")
    .download(templatePath);

  if (storageErr || !blob) {
    const msg = storageErr?.message ?? "blob is null";
    console.error(`[invoice-fill] Template download failed: ${msg}`);
    return json({ error: `Template not found: ${msg}` }, 404);
  }

  const templateBytes = new Uint8Array(await blob.arrayBuffer());

  try {
    const pdfBytes = await buildInvoice(templateBytes, booking);
    const base64 = uint8ArrayToBase64(pdfBytes);
    console.log(`[invoice-fill] PDF generated — ${pdfBytes.byteLength}B for invoice ${booking.invoiceNumber}`);
    return json({ pdf: base64 }, 200);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const stack   = err instanceof Error ? err.stack  : undefined;
    console.error("[invoice-fill] PDF generation failed:", message, stack ?? "");
    return json({ error: `PDF generation failed: ${message}` }, 500);
  }
});

// ── Core invoice builder ───────────────────────────────────────────────────────

async function buildInvoice(
  templateBytes: Uint8Array,
  data: BookingData,
): Promise<Uint8Array> {
  // Load Unicode fonts (cached on warm starts)
  const fontData = await loadFonts();

  // Load template to extract page dimensions
  const templateDoc = await PDFDocument.load(templateBytes);
  const tPages = templateDoc.getPages();
  if (tPages.length === 0) throw new Error("Template PDF has no pages");
  const { width, height } = tPages[0].getSize();

  // Create output document and register fontkit for Unicode (₹, etc.)
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);

  // Embed Noto Sans — handles all Unicode required by invoices
  const [bold, reg] = await Promise.all([
    doc.embedFont(fontData.bold,    { subset: true }),
    doc.embedFont(fontData.regular, { subset: true }),
  ]);

  // Embed entire template as background (page 0)
  const [embeddedTemplate] = await doc.embedPdf(templateDoc, [0]);

  const page = doc.addPage([width, height]);

  // Layer 1: template background (carries branding, logo, header, footer)
  page.drawPage(embeddedTemplate, { x: 0, y: 0, width, height });

  // Layer 2: white mask covering the data zone only
  // Preserves the template's header (top HEADER_H pts) and footer (bottom FOOTER_H pts)
  const HEADER_H = 130;
  const FOOTER_H = 60;
  const M = 48; // horizontal margin

  page.drawRectangle({
    x: M,
    y: FOOTER_H,
    width: width - 2 * M,
    height: height - HEADER_H - FOOTER_H,
    color: C_WHITE,
    opacity: 1,
  });

  // Layer 3: invoice data
  drawInvoiceMeta(page, data, bold, reg, width, height, M);
  const afterBillTo = drawBillTo(page, data, bold, reg, M, height - HEADER_H - 16);
  const afterItems  = drawItemsTable(page, data, bold, reg, M, width, afterBillTo - 20);
  drawTotals(page, data, bold, reg, M, width, afterItems - 16);

  return doc.save();
}

// ── Invoice meta (number + date, right-aligned over template header) ──────────

function drawInvoiceMeta(
  page: ReturnType<PDFDocument["addPage"]>,
  data: BookingData,
  bold: PDFFont,
  reg: PDFFont,
  width: number,
  height: number,
  M: number,
) {
  const topY = height - 28;

  page.drawText("TAX INVOICE", {
    x: width - M - bold.widthOfTextAtSize("TAX INVOICE", 14),
    y: topY,
    size: 14,
    font: bold,
    color: C_WHITE,
  });
  page.drawText(data.invoiceNumber, {
    x: width - M - reg.widthOfTextAtSize(data.invoiceNumber, 11),
    y: topY - 18,
    size: 11,
    font: reg,
    color: C_GOLD,
  });
  page.drawText(data.invoiceDate, {
    x: width - M - reg.widthOfTextAtSize(data.invoiceDate, 9),
    y: topY - 32,
    size: 9,
    font: reg,
    color: C_WHITE,
  });
}

// ── Bill-to + service details row ─────────────────────────────────────────────

function drawBillTo(
  page: ReturnType<PDFDocument["addPage"]>,
  data: BookingData,
  bold: PDFFont,
  reg: PDFFont,
  M: number,
  startY: number,
): number {
  const halfW = 220;
  const rightX = M + halfW + 30;

  // Left column: Bill To
  _label(page, "BILL TO", M, startY, bold);
  let lY = startY - 14;
  lY = _text(page, data.customerName, M, lY, 12, bold, C_BLACK) - 4;
  if (data.customerPhone) lY = _text(page, data.customerPhone, M, lY, 10, reg, C_BLACK);
  if (data.customerEmail) lY = _text(page, data.customerEmail, M, lY, 10, reg, C_BLACK);
  if (data.customerAddress) {
    for (const line of wrapText(data.customerAddress, halfW, reg, 10)) {
      lY = _text(page, line, M, lY, 10, reg, C_BLACK);
    }
  }

  // Right column: Service Details
  _label(page, "SERVICE DETAILS", rightX, startY, bold);
  let rY = startY - 14;
  const rows: [string, string][] = [
    ["Booking No.", data.bookingRef],
    ...(data.serviceDate  ? [["Service Date", data.serviceDate]  as [string, string]] : []),
    ...(data.assignedTo   ? [["Assigned To",  data.assignedTo]   as [string, string]] : []),
    ["Payment",  data.paymentMethod],
    ["Status",   "Completed"],
  ];
  for (const [label, val] of rows) {
    _text(page, `${label}:`, rightX,      rY, 10, reg, C_GRAY);
    _text(page, val,          rightX + 82, rY, 10, reg, C_BLACK);
    rY -= 14;
  }

  return Math.min(lY, rY);
}

// ── Items table ───────────────────────────────────────────────────────────────

function drawItemsTable(
  page: ReturnType<PDFDocument["addPage"]>,
  data: BookingData,
  bold: PDFFont,
  reg: PDFFont,
  M: number,
  pageWidth: number,
  startY: number,
): number {
  const TW = pageWidth - 2 * M;

  _label(page, "SERVICES", M, startY, bold);
  let y = startY - 12;

  if (data.items.length === 0) {
    page.drawRectangle({ x: M, y: y - 20, width: TW, height: 22, color: C_STRIPE });
    _text(page, "Service",      M + 8,        y - 14, 10, reg,  C_BLACK);
    _text(page, data.grandTotal, M + TW - 60, y - 14, 10, bold, C_BLACK);
    return y - 22;
  }

  // Header row
  page.drawRectangle({ x: M, y: y - 20, width: TW, height: 22, color: C_DARK });
  _th(page, "#",          M + 6,          y - 13, bold);
  _th(page, "Service",    M + 28,         y - 13, bold);
  _th(page, "Qty",        M + TW * 0.54,  y - 13, bold);
  _th(page, "Unit Price", M + TW * 0.63,  y - 13, bold);
  _th(page, "Amount",     M + TW * 0.83,  y - 13, bold);
  y -= 20;

  for (let i = 0; i < data.items.length; i++) {
    const item = data.items[i];
    const rowH = 20;
    page.drawRectangle({ x: M, y: y - rowH, width: TW, height: rowH,
      color: i % 2 === 0 ? C_WHITE : C_STRIPE });
    _td(page, `${i + 1}`,            M + 6,          y - 13, reg);
    _td(page, clip(item.name, 40),    M + 28,         y - 13, reg);
    _td(page, item.qty,               M + TW * 0.54,  y - 13, reg);
    _td(page, item.unitPrice,         M + TW * 0.63,  y - 13, reg);
    _td(page, item.totalPrice,        M + TW * 0.83,  y - 13, reg);
    y -= rowH;
  }

  if (data.addons.length > 0) {
    y -= 14;
    _label(page, "ADD-ONS", M, y, bold);
    y -= 12;

    page.drawRectangle({ x: M, y: y - 20, width: TW, height: 22, color: C_DARK });
    _th(page, "Add-on", M + 28,        y - 13, bold);
    _th(page, "Price",  M + TW * 0.83, y - 13, bold);
    y -= 20;

    for (let i = 0; i < data.addons.length; i++) {
      const addon = data.addons[i];
      page.drawRectangle({ x: M, y: y - 20, width: TW, height: 20,
        color: i % 2 === 0 ? C_WHITE : C_STRIPE });
      _td(page, clip(addon.name, 55), M + 28,        y - 13, reg);
      _td(page, addon.price,          M + TW * 0.83, y - 13, reg);
      y -= 20;
    }
  }

  return y;
}

// ── Totals block ──────────────────────────────────────────────────────────────

function drawTotals(
  page: ReturnType<PDFDocument["addPage"]>,
  data: BookingData,
  bold: PDFFont,
  reg: PDFFont,
  M: number,
  pageWidth: number,
  startY: number,
) {
  const totalsX = pageWidth - M - 220;
  let y = startY;

  const rows: [string, string][] = [["Subtotal", data.subtotal]];

  if (data.taxAmount && data.taxAmount !== "Rs.0.00" && data.taxAmount !== "₹0.00") {
    rows.push([data.taxLabel || "Taxes & Fees", data.taxAmount]);
  }
  if (data.discount && data.discount !== "Rs.0.00" && data.discount !== "₹0.00") {
    rows.push(["Discount", `-${data.discount}`]);
  }

  for (const [label, val] of rows) {
    _text(page, label, totalsX,       y, 10, reg, C_GRAY);
    _text(page, val,   totalsX + 130, y, 10, reg, C_GRAY);
    y -= 15;
  }

  page.drawLine({
    start: { x: totalsX,       y },
    end:   { x: totalsX + 200, y },
    thickness: 0.5,
    color: C_BORDER,
  });
  y -= 14;

  _text(page, "Total Amount",   totalsX,       y, 12, bold, C_BLACK);
  _text(page, data.grandTotal,  totalsX + 120, y, 12, bold, C_BLACK);
}

// ── Drawing helpers ───────────────────────────────────────────────────────────

function _label(
  page: ReturnType<PDFDocument["addPage"]>,
  text: string, x: number, y: number, font: PDFFont,
) {
  page.drawText(text, { x, y, size: 8, font, color: C_LGRAY });
}

function _text(
  page: ReturnType<PDFDocument["addPage"]>,
  text: string, x: number, y: number, size: number, font: PDFFont,
  color: ReturnType<typeof rgb>,
): number {
  page.drawText(text, { x, y, size, font, color });
  return y - (size + 3);
}

function _th(
  page: ReturnType<PDFDocument["addPage"]>,
  text: string, x: number, y: number, font: PDFFont,
) {
  page.drawText(text, { x, y, size: 9, font, color: C_WHITE });
}

function _td(
  page: ReturnType<PDFDocument["addPage"]>,
  text: string, x: number, y: number, font: PDFFont,
) {
  page.drawText(text, { x, y, size: 9, font, color: C_BLACK });
}

function clip(text: string, maxChars: number): string {
  return text.length > maxChars ? text.substring(0, maxChars - 1) + "…" : text;
}

function wrapText(text: string, maxPts: number, font: PDFFont, size: number): string[] {
  const words = text.split(" ");
  const lines: string[] = [];
  let line = "";
  for (const w of words) {
    const test = line ? `${line} ${w}` : w;
    if (font.widthOfTextAtSize(test, size) > maxPts && line) {
      lines.push(line);
      line = w;
    } else {
      line = test;
    }
  }
  if (line) lines.push(line);
  return lines;
}
