/**
 * Static export: `npm run build` writes plain HTML/CSS/JS to ./out.
 * No Node server in production, no secrets in the bundle — Caddy serves ./out
 * (see Dockerfile / Caddyfile). Everything live comes from the UDrive API.
 *
 * @type {import('next').NextConfig}
 */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  poweredByHeader: false,
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default nextConfig;
