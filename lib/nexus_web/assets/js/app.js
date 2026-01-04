// Nexus Web Dashboard JavaScript

import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import cytoscape from "cytoscape";

// Make cytoscape available globally for debugging
window.cytoscape = cytoscape;

// Hooks
let Hooks = {};

// DAG Graph Hook - Renders interactive task dependency graph using Cytoscape
Hooks.DagGraph = {
  mounted() {
    console.log("DagGraph hook mounted");
    this.retryCount = 0;
    this.maxRetries = 50; // 50 * 100ms = 5 seconds max wait
    this.waitForConnectionAndData();
  },

  updated() {
    console.log("DagGraph hook updated");
    this.initializeOrUpdate();
  },

  // Wait for both LiveSocket connection AND data to be available
  waitForConnectionAndData() {
    const nodes = JSON.parse(this.el.dataset.nodes || "[]");
    const isConnected = window.liveSocket && window.liveSocket.isConnected();

    console.log(
      `Check: nodes=${nodes.length}, connected=${isConnected}, attempt=${this.retryCount + 1}`,
    );

    if (nodes.length > 0 && isConnected) {
      console.log(
        "Data available and LiveSocket connected, initializing graph",
      );
      this.initializeOrUpdate();
    } else if (this.retryCount < this.maxRetries) {
      this.retryCount++;
      setTimeout(() => this.waitForConnectionAndData(), 100);
    } else {
      console.warn("Gave up waiting after 5 seconds");
      // Try anyway as a fallback
      if (nodes.length > 0) {
        console.log("Forcing init despite connection status");
        this.initializeOrUpdate();
      }
    }
  },

  initializeOrUpdate() {
    const nodes = JSON.parse(this.el.dataset.nodes || "[]");
    const edges = JSON.parse(this.el.dataset.edges || "[]");
    const statuses = JSON.parse(this.el.dataset.statuses || "{}");

    if (nodes.length === 0) {
      console.log("No nodes yet, skipping render");
      return;
    }

    if (!this.cy) {
      console.log("Initializing graph for the first time");
      this.renderGraph();
    } else {
      console.log("Updating existing graph");
      this.updateNodeColors(statuses);
    }
  },

  renderGraph() {
    const container = this.el;

    console.log("=== DAG DATA ATTRIBUTES ===");
    console.log("data-nodes:", this.el.dataset.nodes);
    console.log("data-edges:", this.el.dataset.edges);
    console.log("data-statuses:", this.el.dataset.statuses);

    const nodes = JSON.parse(this.el.dataset.nodes || "[]");
    const edges = JSON.parse(this.el.dataset.edges || "[]");
    const statuses = JSON.parse(this.el.dataset.statuses || "{}");

    console.log("=== DAG Rendering ===");
    console.log("Nodes:", nodes.length, nodes);
    console.log("Edges:", edges.length, edges);
    console.log("Statuses:", statuses);

    if (edges.length === 0) {
      console.error(
        "⚠️ NO EDGES FOUND! Check your config file and DAG building logic.",
      );
    }

    // Build elements array (flat format works better for initial rendering)
    const elements = [
      ...nodes.map((n) => ({
        group: "nodes",
        data: { id: n.id, label: n.label },
        classes: statuses[n.id] || "pending",
      })),
      ...edges.map((e, i) => ({
        group: "edges",
        data: {
          id: "edge_" + i,
          source: e.from,
          target: e.to,
        },
      })),
    ];

    console.log("Total elements:", elements.length);

    console.log("Creating cytoscape instance...");
    this.cy = cytoscape({
      container: container,
      elements: elements,
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            "text-valign": "center",
            "text-halign": "center",
            "background-color": "#111",
            "border-color": "#333",
            "border-width": 1,
            color: "#fff",
            "font-size": "12px",
            "font-family": "ui-monospace, monospace",
            width: 160,
            height: 40,
            shape: "rectangle",
            "text-wrap": "wrap",
            "text-max-width": 140,
          },
        },
        {
          selector: "node.pending",
          style: { "background-color": "#111", "border-color": "#333" },
        },
        {
          selector: "node.running",
          style: {
            "background-color": "#0a2a1f",
            "border-color": "#00e599",
            "border-width": 2,
          },
        },
        {
          selector: "node.success",
          style: { "background-color": "#0a2a1f", "border-color": "#00e599" },
        },
        {
          selector: "node.failed",
          style: { "background-color": "#1a0a0a", "border-color": "#ef4444" },
        },
        {
          selector: "node.skipped",
          style: { "background-color": "#1a1a0a", "border-color": "#eab308" },
        },
        {
          selector: "edge",
          style: {
            width: 1,
            "line-color": "#333",
            "target-arrow-color": "#00e599",
            "target-arrow-shape": "triangle",
            "arrow-scale": 1,
            "curve-style": "bezier",
          },
        },
        {
          selector: "node:selected",
          style: {
            "border-width": 2,
            "border-color": "#00e599",
            "overlay-opacity": 0.1,
            "overlay-color": "#00e599",
          },
        },
      ],
      layout: {
        name: "breadthfirst",
        directed: true,
        padding: 50,
        spacingFactor: 1.75,
        avoidOverlap: true,
      },
      wheelSensitivity: 0.2,
      minZoom: 0.2,
      maxZoom: 2.5,
    });

    console.log(
      "Cytoscape created. Nodes:",
      this.cy.nodes().length,
      "Edges:",
      this.cy.edges().length,
    );

    // Store hook reference for event handlers
    const hook = this;
    const cy = this.cy;

    // Bind events after a short delay to ensure canvas is ready
    setTimeout(() => {
      console.log("=== BINDING CYTOSCAPE EVENTS ===");

      // Click handler - use stored hook reference
      cy.on("tap", "node", (evt) => {
        const taskId = evt.target.id();
        console.log("=== NODE CLICKED ===");
        console.log("Task ID:", taskId);
        console.log("Hook exists:", !!hook);
        console.log("pushEvent type:", typeof hook.pushEvent);
        console.log("liveSocket connected:", window.liveSocket?.isConnected());

        // Try pushEvent
        if (hook.pushEvent && window.liveSocket?.isConnected()) {
          console.log("Calling pushEvent...");
          hook.pushEvent("select_task", { task: taskId });
          console.log("pushEvent called successfully");
        } else {
          console.warn("LiveSocket not ready, using direct navigation");
          window.location.href = `/task/${taskId}`;
        }
      });

      // Double-click to run
      cy.on("dbltap", "node", (evt) => {
        const taskId = evt.target.id();
        console.log("Node double-tapped:", taskId);
        try {
          hook.pushEvent("run_task", { task: taskId });
        } catch (e) {
          console.error("pushEvent failed:", e);
        }
      });

      // Also bind a general tap event to debug
      cy.on("tap", (evt) => {
        console.log(
          "Cytoscape tap event:",
          evt.target.id ? evt.target.id() : "background",
        );
      });

      console.log("Events bound successfully");
    }, 100);

    // Fit view after layout completes
    this.cy.on("layoutstop", () => {
      this.cy.fit(40);
      // Debug: check all edges
      console.log("=== EDGE DEBUG ===");
      console.log("Total edges in cy:", this.cy.edges().length);
      this.cy.edges().forEach((edge) => {
        const src = edge.source();
        const tgt = edge.target();
        const srcPos = src.position();
        const tgtPos = tgt.position();
        console.log(
          `Edge ${edge.id()}: ${src.id()}(${srcPos.x.toFixed(0)},${srcPos.y.toFixed(0)}) -> ${tgt.id()}(${tgtPos.x.toFixed(0)},${tgtPos.y.toFixed(0)})`,
        );
      });
    });
  },

  updateNodeColors(statuses) {
    if (!this.cy) return;
    Object.entries(statuses).forEach(([nodeId, status]) => {
      const node = this.cy.getElementById(nodeId);
      if (node.length) {
        node.removeClass("pending running success failed skipped");
        node.addClass(status);
      }
    });
  },

  destroyed() {
    if (this.cy) {
      this.cy.destroy();
    }
  },
};

// Log Stream Hook - Auto-scrolls log output
Hooks.LogStream = {
  mounted() {
    this.scrollToBottom();
  },

  updated() {
    if (this.isAtBottom()) {
      this.scrollToBottom();
    }
  },

  isAtBottom() {
    const threshold = 50;
    return (
      this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight <
      threshold
    );
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

// Sidebar Hook - no longer used, kept empty for compatibility
Hooks.Sidebar = {
  mounted() {},
};

// Initialize LiveSocket
console.log("=== INITIALIZING LIVEVIEW ===");
console.log("Hooks available:", Object.keys(Hooks));

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

console.log("LiveSocket created with hooks:", liveSocket);

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: "#6366f1" },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// Connect if there are any LiveViews on the page
liveSocket.connect();

// Expose for debugging
window.liveSocket = liveSocket;

// Sidebar toggle - use body class (survives LiveView re-renders)
(function () {
  const KEY = "nexus-sidebar-collapsed";

  // Apply state from localStorage to body class
  function applyState() {
    if (localStorage.getItem(KEY) === "true") {
      document.body.classList.add("sidebar-collapsed");
    } else {
      document.body.classList.remove("sidebar-collapsed");
    }
    // Remove preload class from html (was set synchronously to prevent flash)
    document.documentElement.classList.remove("sidebar-collapsed-preload");
    // Enable transitions now that state is applied
    document.body.classList.add("sidebar-ready");
  }

  function bindToggle() {
    const toggle = document.getElementById("sidebar-toggle");
    if (!toggle || toggle._bound) return;
    toggle._bound = true;

    toggle.onclick = function (e) {
      e.stopPropagation();
      if (document.body.classList.contains("sidebar-collapsed")) {
        document.body.classList.remove("sidebar-collapsed");
        localStorage.setItem(KEY, "false");
      } else {
        document.body.classList.add("sidebar-collapsed");
        localStorage.setItem(KEY, "true");
      }
    };
  }

  // Bind toggle on DOM ready, then apply state
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindToggle();
      applyState();
    });
  } else {
    bindToggle();
    applyState();
  }

  // Re-bind after LiveView navigation (new toggle element)
  window.addEventListener("phx:page-loading-stop", bindToggle);
})();
