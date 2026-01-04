// Tailwind CSS configuration for Nexus Web Dashboard

const plugin = require("tailwindcss/plugin");

module.exports = {
  content: ["./js/**/*.js", "../**/*.ex", "../**/*.heex"],
  theme: {
    extend: {
      colors: {
        brand: "#6366f1",
      },
    },
  },
  plugins: [
    // Custom plugin for forms if needed
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ]),
    ),
  ],
};
