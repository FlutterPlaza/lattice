// ==========================================================================
// Lattice Documentation - Application JavaScript
// ==========================================================================

const pages = {
  'getting-started': 'pages/getting-started.md',
  'protocol': 'pages/protocol.md',
  'server': 'pages/server.md',
  'client': 'pages/client.md',
  'deployment': 'pages/deployment.md',
  'platforms': 'pages/platforms.md',
  'monitoring': 'pages/monitoring.md',
  'security': 'pages/security.md',
  'ring-protocol': 'pages/ring-protocol.md',
  'troubleshooting': 'pages/troubleshooting.md',
  'api-reference': 'pages/api-reference.md',
};

// --------------------------------------------------------------------------
// Markdown rendering
// --------------------------------------------------------------------------

/**
 * Loads and renders a markdown page into the content area.
 * @param {string} pageId - The page identifier (hash without #).
 */
async function loadPage(pageId) {
  const content = document.getElementById('content');
  const path = pages[pageId] || pages['getting-started'];

  // Resolve the actual pageId if the requested one was invalid.
  if (!pages[pageId]) {
    pageId = 'getting-started';
  }

  content.innerHTML = '<div class="loading">Loading...</div>';

  try {
    const response = await fetch(path);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const markdown = await response.text();
    content.innerHTML = marked.parse(markdown);
    content.scrollTop = 0;
    window.scrollTo(0, 0);
  } catch (e) {
    content.innerHTML =
      '<h1>Page not found</h1>' +
      '<p>The requested documentation page could not be loaded.</p>' +
      '<p>Error: ' + e.message + '</p>';
  }

  updateActiveLink(pageId);
}

// --------------------------------------------------------------------------
// Navigation
// --------------------------------------------------------------------------

/**
 * Updates the active state of sidebar navigation links.
 * @param {string} activeId - The page identifier to mark as active.
 */
function updateActiveLink(activeId) {
  const links = document.querySelectorAll('#sidebar ul li a');
  links.forEach(function (link) {
    const href = link.getAttribute('href');
    if (href === '#' + activeId) {
      link.classList.add('active');
    } else {
      link.classList.remove('active');
    }
  });
}

// Handle hash changes.
window.addEventListener('hashchange', function () {
  const pageId = window.location.hash.slice(1) || 'getting-started';
  loadPage(pageId);
  closeMobileMenu();
});

// Handle sidebar link clicks.
document.addEventListener('DOMContentLoaded', function () {
  const links = document.querySelectorAll('#sidebar ul li a');
  links.forEach(function (link) {
    link.addEventListener('click', function () {
      closeMobileMenu();
    });
  });
});

// --------------------------------------------------------------------------
// Mobile menu
// --------------------------------------------------------------------------

const menuToggle = document.getElementById('menu-toggle');
const sidebar = document.getElementById('sidebar');
const overlay = document.getElementById('overlay');

if (menuToggle) {
  menuToggle.addEventListener('click', function () {
    sidebar.classList.toggle('open');
    overlay.classList.toggle('open');
  });
}

if (overlay) {
  overlay.addEventListener('click', function () {
    closeMobileMenu();
  });
}

function closeMobileMenu() {
  sidebar.classList.remove('open');
  overlay.classList.remove('open');
}

// --------------------------------------------------------------------------
// Theme switching
// --------------------------------------------------------------------------

const themeToggle = document.getElementById('theme-toggle');

function getStoredTheme() {
  return localStorage.getItem('lattice-docs-theme');
}

function setTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('lattice-docs-theme', theme);
}

// Initialize theme.
(function () {
  var stored = getStoredTheme();
  if (stored) {
    setTheme(stored);
  } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    setTheme('dark');
  }
})();

if (themeToggle) {
  themeToggle.addEventListener('click', function () {
    var current = document.documentElement.getAttribute('data-theme');
    setTheme(current === 'dark' ? 'light' : 'dark');
  });
}

// --------------------------------------------------------------------------
// Initial page load
// --------------------------------------------------------------------------

(function () {
  var pageId = window.location.hash.slice(1) || 'getting-started';
  loadPage(pageId);
})();
