import { themes as prismThemes } from "prism-react-renderer";
import type { Config } from "@docusaurus/types";
import type * as Preset from "@docusaurus/preset-classic";
import * as fs from "fs";
import * as path from "path";

// Read version from mix.exs
function getVersion(): string {
  try {
    const mixPath = path.join(__dirname, "..", "mix.exs");
    const content = fs.readFileSync(mixPath, "utf-8");
    const match = content.match(/@version\s+"([^"]+)"/);
    return match ? match[1] : "0.1.0";
  } catch {
    return "0.1.0";
  }
}

const NEXUS_VERSION = getVersion();

const config: Config = {
  title: "Nexus",
  tagline: "Distributed task runner with SSH support",
  favicon: "img/favicon.ico",

  future: {
    v4: true,
  },

  url: "https://humancorp.xyz",
  baseUrl: "/nexus/",

  organizationName: "manav03panchal",
  projectName: "nexus",

  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",

  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },

  presets: [
    [
      "classic",
      {
        docs: {
          routeBasePath: "/",
          sidebarPath: "./sidebars.ts",
          editUrl: "https://github.com/manav03panchal/nexus/tree/main/website/",
        },
        blog: false,
        theme: {
          customCss: "./src/css/custom.css",
        },
      } satisfies Preset.Options,
    ],
  ],

  customFields: {
    nexusVersion: NEXUS_VERSION,
  },

  themeConfig: {
    colorMode: {
      defaultMode: "dark",
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: `Nexus v${NEXUS_VERSION}`,
      items: [
        {
          type: "docSidebar",
          sidebarId: "docsSidebar",
          position: "left",
          label: "Docs",
        },
        {
          href: "https://github.com/manav03panchal/nexus",
          label: "GitHub",
          position: "right",
        },
      ],
    },
    footer: {
      style: "dark",
      links: [
        {
          title: "Docs",
          items: [
            {
              label: "Getting Started",
              to: "/getting-started",
            },
            {
              label: "Configuration",
              to: "/configuration",
            },
            {
              label: "CLI Reference",
              to: "/cli",
            },
          ],
        },
        {
          title: "More",
          items: [
            {
              label: "GitHub",
              href: "https://github.com/manav03panchal/nexus",
            },
          ],
        },
      ],
      copyright: `Copyright ${new Date().getFullYear()} Nexus`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ["elixir", "bash"],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
