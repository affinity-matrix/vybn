import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://vybn.sh",
  integrations: [
    starlight({
      title: "vybn",
      logo: {
        src: "./src/assets/vybn-logo.svg",
      },
      description:
        "CLI for managing Claude Code on a cloud virtual machine. Persistent tmux sessions, connect from anywhere.",
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/affinity-matrix/vybn",
        },
      ],
      customCss: ["./src/styles/custom.css"],
      sidebar: [
        {
          label: "Start Here",
          items: [
            { label: "Introduction", slug: "index" },
            { label: "Prerequisites", slug: "guides/prerequisites" },
            { label: "Getting Started", slug: "getting-started" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "Commands", slug: "commands" },
            { label: "Configuration", slug: "configuration" },
            { label: "Architecture", slug: "architecture" },
          ],
        },
        {
          label: "Guides",
          items: [
            { label: "Tailscale Setup", slug: "guides/tailscale" },
            { label: "IAP Setup", slug: "guides/iap" },
            { label: "SSH Provider", slug: "guides/ssh-provider" },
            { label: "Mobile SSH", slug: "guides/mobile-ssh" },
            { label: "Toolchains", slug: "guides/toolchains" },
            { label: "Git & GitHub", slug: "guides/git-github" },
            { label: "Working with tmux", slug: "guides/tmux" },
          ],
        },
        {
          label: "Help",
          items: [
            { label: "Troubleshooting", slug: "troubleshooting" },
            {
              label: "Feature Requests",
              link: "https://github.com/affinity-matrix/vybn/issues/new/choose",
              attrs: { target: "_blank" },
            },
          ],
        },
      ],
    }),
  ],
});
