import type { MetadataRoute } from "next";

import { siteUrl } from "@/content/site-url";



const base = siteUrl();

const lastModified = new Date("2026-10-13");

export default function sitemap(): MetadataRoute.Sitemap {
  const routes = ["", "/about", "/services", "/download", "/privacy", "/terms"];
  return routes.map((route) => ({
    url: `${base}${route}`,
    lastModified,
    changeFrequency: route === "" ? ("weekly" as const) : ("monthly" as const),
    priority: route === "" ? 1 : route === "/download" ? 0.9 : 0.7,
  }));
}