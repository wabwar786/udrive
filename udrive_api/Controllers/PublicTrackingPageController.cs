using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace UDrive.Api.Controllers;

/// <summary>
/// The page a shared trip link opens: <c>/track/{token}</c>.
/// </summary>
/// <remarks>
/// The customer app has always shared <c>{api}/track/{token}</c>, but no page
/// answered that address, so a shared link showed an error. This page needs no
/// sign-in: it shows a live map that reads <c>/api/v1/public/tracking/{token}</c>
/// every 5 seconds. That route already hides the trip code and the driver's
/// surname, and stops answering when the trip ends or the link expires.
/// </remarks>
[ApiController]
[AllowAnonymous]
[ApiExplorerSettings(IgnoreApi = true)]
public sealed class PublicTrackingPageController : ControllerBase
{
    private static readonly Regex TokenShape = new("^[0-9a-f]{40,128}$", RegexOptions.Compiled);

    [HttpGet("/track/{token}")]
    public ContentResult Track(string token)
    {
        // Only a token of the right shape is ever written into the page.
        var safe = TokenShape.IsMatch(token ?? string.Empty) ? token! : string.Empty;

        // OpenStreetMap's tile servers refuse requests with no Referer, and the
        // API sends "no-referrer" everywhere else; this page needs the origin.
        Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
        Response.Headers["Cache-Control"] = "no-store";
        return Content(Page.Replace("__TOKEN__", safe), "text/html; charset=utf-8");
    }

    private const string Page = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>UDrive · Live trip</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin="">
<style>
  :root { --navy:#0B1B33; --lime:#C6F432; --ink:#12231e; --muted:#5d716a; --line:#dce7e2; }
  * { box-sizing:border-box }
  html,body { margin:0; height:100%; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; color:var(--ink); background:#f4f7f6 }
  .shell { display:flex; flex-direction:column; height:100% }
  header { background:var(--navy); color:#fff; padding:12px 16px; display:flex; align-items:center; gap:12px }
  header .brand { font-weight:800; font-size:18px } header .brand span { color:var(--lime) }
  header .ref { margin-left:auto; font-size:12px; opacity:.8 }
  #map { flex:1; min-height:300px }
  .card { background:#fff; border-top:1px solid var(--line); padding:12px 16px 16px; display:grid; gap:8px }
  .row { display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap }
  .title { font-weight:800; font-size:16px }
  .muted { color:var(--muted); font-size:13px }
  .badge { display:inline-flex; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:800; background:#dff6ec; color:#087650 }
  .badge.stale { background:#fff2cf; color:#7a5300 } .badge.sos { background:#ffe1e5; color:#a62032 }
  .tools { position:absolute; z-index:500; right:12px; top:76px; display:flex; flex-direction:column; gap:8px }
  .tools button { min-height:44px; border:0; border-radius:12px; padding:0 14px; font-weight:800; background:#fff; color:var(--navy); box-shadow:0 6px 18px #0b1b3333; cursor:pointer }
  .tools button.on { background:var(--lime) }
  .ended { margin:auto; text-align:center; padding:40px 20px; max-width:420px }
  .ended h1 { font-size:20px; margin:0 0 8px }
  .car { background:transparent; border:0 }
</style>
</head>
<body>
<div class="shell" id="shell">
  <header><div class="brand">U<span>Drive</span></div><div>Live trip</div><div class="ref" id="ref"></div></header>
  <div id="map" role="img" aria-label="Map showing the car's live position"></div>
  <div class="tools">
    <button id="follow" class="on" type="button">Following car</button>
    <button id="fit" type="button">Whole trip</button>
    <button id="sat" type="button">Satellite</button>
  </div>
  <div class="card">
    <div class="row"><div class="title" id="who">Loading…</div><span class="badge" id="status">—</span></div>
    <div class="muted" id="route"></div>
    <div class="muted" id="updated"></div>
  </div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" crossorigin=""></script>
<script>
(function () {
  var token = "__TOKEN__";
  var shell = document.getElementById("shell");
  function ended(title, text) {
    shell.innerHTML = '<div class="ended"><h1></h1><p class="muted"></p></div>';
    shell.querySelector("h1").textContent = title;
    shell.querySelector("p").textContent = text;
  }
  if (!token) { ended("This link is not valid", "Ask for a new tracking link."); return; }
  if (!window.L) { ended("The map could not load", "Check the internet connection and open the link again."); return; }

  var map = L.map("map").setView([34.37, 73.47], 13);
  var streets = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: "&copy; OpenStreetMap contributors" }).addTo(map);
  var satellite = L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", { maxZoom: 19, attribution: "Imagery &copy; Esri" });
  var path = L.polyline([], { color: "#148f69", weight: 5 }).addTo(map);
  var pickup = L.circleMarker([0, 0], { radius: 9, color: "#fff", weight: 3, fillColor: "#2676d8", fillOpacity: 1 }).bindTooltip("Pickup");
  var dest = L.circleMarker([0, 0], { radius: 9, color: "#fff", weight: 3, fillColor: "#ee7b24", fillOpacity: 1 }).bindTooltip("Destination");
  var car = L.marker([0, 0], { zIndexOffset: 1000 });
  var follow = true, first = true, sat = false, points = [];

  function icon(heading, sos) {
    var fill = sos ? "#e83b4e" : "#0B1B33";
    return L.divIcon({ className: "car", iconSize: [40, 40], iconAnchor: [20, 20],
      html: '<div style="width:40px;height:40px;transform:rotate(' + Math.round(heading || 0) + 'deg)"><svg width="40" height="40" viewBox="0 0 40 40"><circle cx="20" cy="20" r="17" fill="' + (sos ? "#e83b4e" : "#C6F432") + '" opacity="0.35"/><circle cx="20" cy="20" r="10" fill="' + fill + '" stroke="#fff" stroke-width="3"/><path d="M20 4 L25 13 L20 11 L15 13 Z" fill="' + fill + '" stroke="#fff" stroke-width="1.5"/></svg></div>' });
  }
  function ago(iso) {
    var s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
    if (s < 60) return s + " seconds ago";
    var m = Math.round(s / 60); return m < 60 ? m + " min ago" : Math.round(m / 60) + " h ago";
  }
  function setFollow(on) { follow = on; var b = document.getElementById("follow"); b.className = on ? "on" : ""; b.textContent = on ? "Following car" : "Follow car"; }
  map.on("dragstart", function () { setFollow(false); });
  document.getElementById("follow").onclick = function () { setFollow(true); var ll = car.getLatLng(); if (ll && ll.lat) map.setView(ll, Math.max(map.getZoom(), 16)); };
  document.getElementById("fit").onclick = function () { if (points.length) { setFollow(false); map.fitBounds(points, { padding: [40, 40], maxZoom: 16 }); } };
  document.getElementById("sat").onclick = function () {
    sat = !sat; this.textContent = sat ? "Streets" : "Satellite";
    if (sat) { map.removeLayer(streets); satellite.addTo(map); } else { map.removeLayer(satellite); streets.addTo(map); }
  };

  function draw(t) {
    document.getElementById("ref").textContent = t.bookingReference || "";
    document.getElementById("who").textContent = (t.driverName ? t.driverName + " · " : "") + (t.vehicle || "Vehicle") + (t.registrationNumber ? " · " + t.registrationNumber : "");
    document.getElementById("route").textContent = (t.pickupLabel || "Pickup") + " → " + (t.destinationLabel || "Destination");
    var loc = t.driverLocation, badge = document.getElementById("status");
    badge.textContent = loc && loc.emergency ? "Emergency" : loc && loc.stale ? "Location delayed" : (t.tripStatus || "Live").replace(/([a-z])([A-Z])/g, "$1 $2");
    badge.className = "badge" + (loc && loc.emergency ? " sos" : loc && loc.stale ? " stale" : "");
    document.getElementById("updated").textContent = loc ? "Last update " + ago(loc.serverTimestamp) + (loc.speedKph != null ? " · " + Math.round(loc.speedKph) + " km/h" : "") : "Waiting for the car's location…";

    points = (t.recentPath || []).map(function (p) { return [p.latitude, p.longitude]; });
    path.setLatLngs(points);
    if (t.pickupLatitude != null && t.pickupLongitude != null) { pickup.setLatLng([t.pickupLatitude, t.pickupLongitude]).addTo(map); points.push([t.pickupLatitude, t.pickupLongitude]); }
    if (t.destinationLatitude != null && t.destinationLongitude != null) { dest.setLatLng([t.destinationLatitude, t.destinationLongitude]).addTo(map); points.push([t.destinationLatitude, t.destinationLongitude]); }
    if (loc) {
      car.setLatLng([loc.latitude, loc.longitude]).setIcon(icon(loc.heading, loc.emergency)).addTo(map);
      points.push([loc.latitude, loc.longitude]);
      if (first) { map.setView([loc.latitude, loc.longitude], 16); }
      else if (follow) { map.panTo([loc.latitude, loc.longitude]); }
    } else if (first && points.length) { map.fitBounds(points, { padding: [40, 40], maxZoom: 16 }); }
    first = false;
  }

  var timer = null;
  function load() {
    fetch("/api/v1/public/tracking/" + token, { headers: { "Accept": "application/json" }, cache: "no-store" })
      .then(function (r) { return r.json().then(function (b) { return { ok: r.ok, status: r.status, body: b }; }); })
      .then(function (res) {
        if (res.ok && res.body && res.body.data) { draw(res.body.data); return; }
        if (res.status === 404) { clearInterval(timer); ended("This trip is no longer shared", "The trip has ended or the link has expired."); }
      })
      .catch(function () { document.getElementById("updated").textContent = "Connection lost — trying again…"; });
  }
  load();
  timer = setInterval(load, 5000);
})();
</script>
</body>
</html>
""";
}
