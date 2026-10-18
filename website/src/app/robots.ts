import type { MetadataRoute } from "next";

import { siteUrl } from "@/content/site-url";



const base = siteUrl();

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: `${base}/sitemap.xml`,
    host: base,
  };
}