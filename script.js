const container = document.getElementById('neural-bg');
const canvas = document.createElement('canvas');
container.appendChild(canvas);
const ctx = canvas.getContext('2d');

let width, height;

function setSize() {
  width = canvas.width = window.innerWidth;
  height = canvas.height = window.innerHeight;
}
setSize();
window.addEventListener('resize', setSize);

const nodes = [];
// Adjust density based on screen width
const numNodes = Math.min(Math.floor((window.innerWidth * window.innerHeight) / 10000), 150);

for (let i = 0; i < numNodes; i++) {
  nodes.push({
    x: Math.random() * width,
    y: Math.random() * height,
    vx: (Math.random() - 0.5) * 1.5,
    vy: (Math.random() - 0.5) * 1.5,
    size: Math.random() * 2 + 0.5,
    // 80% cyan, 20% purple nodes for variety
    baseColor: Math.random() > 0.8 ? '#7000ff' : '#00f3ff'
  });
}

const mouse = { x: -1000, y: -1000 };

window.addEventListener('mousemove', (e) => {
  mouse.x = e.clientX;
  mouse.y = e.clientY;
});

window.addEventListener('mouseout', () => {
  mouse.x = -1000;
  mouse.y = -1000;
});

function drawCircle(ctx, x, y, r, color) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
}

function hexToRgba(hex, alpha = 1) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function animate() {
  ctx.clearRect(0, 0, width, height);

  // To optimize, cache a couple max distance calculations
  const linkDist = 130;
  const mouseDist = 200;

  for (let i = 0; i < numNodes; i++) {
    const node = nodes[i];
    node.x += node.vx;
    node.y += node.vy;

    // Smooth boundary bouncing
    if (node.x < 0) { node.x = 0; node.vx *= -1; }
    if (node.x > width) { node.x = width; node.vx *= -1; }
    if (node.y < 0) { node.y = 0; node.vy *= -1; }
    if (node.y > height) { node.y = height; node.vy *= -1; }

    const dxMouse = mouse.x - node.x;
    const dyMouse = mouse.y - node.y;
    const distToMouse = Math.sqrt(dxMouse * dxMouse + dyMouse * dyMouse);

    // Subtle interactivity - nodes slightly repel from cursor to look "alive"
    if (distToMouse < 100) {
      node.x -= dxMouse * 0.015;
      node.y -= dyMouse * 0.015;
    }

    // Draw node glowing effect
    ctx.shadowBlur = 10;
    ctx.shadowColor = node.baseColor;
    drawCircle(ctx, node.x, node.y, node.size, hexToRgba(node.baseColor, 0.8));
    ctx.shadowBlur = 0; // reset

    // Connections between nodes
    for (let j = i + 1; j < numNodes; j++) {
      const other = nodes[j];
      const dx = other.x - node.x;
      const dy = other.y - node.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < linkDist) {
        ctx.beginPath();
        ctx.moveTo(node.x, node.y);
        ctx.lineTo(other.x, other.y);
        ctx.lineWidth = (1 - dist / linkDist);

        // Linear gradient for connections merging colors
        const grad = ctx.createLinearGradient(node.x, node.y, other.x, other.y);
        grad.addColorStop(0, hexToRgba(node.baseColor, (1 - dist / linkDist) * 0.6));
        grad.addColorStop(1, hexToRgba(other.baseColor, (1 - dist / linkDist) * 0.6));

        ctx.strokeStyle = grad;
        ctx.stroke();
      }
    }

    // Direct mouse connections (Neural probing effect)
    if (distToMouse < mouseDist) {
      ctx.beginPath();
      ctx.moveTo(node.x, node.y);
      ctx.lineTo(mouse.x, mouse.y);
      ctx.lineWidth = 1;
      ctx.strokeStyle = hexToRgba('#00f3ff', (1 - distToMouse / mouseDist) * 0.5);
      ctx.stroke();
    }
  }

  requestAnimationFrame(animate);
}

// Start
animate();

// Splash Screen Animation Sequence
setTimeout(() => {
  const splashLogo = document.getElementById('splash-logo');
  const splashSpinTarget = document.querySelector('.splash-spin-target');
  const targetSvg = document.querySelector('.logo-8'); // Use logo-8 parent to get precise layout
  const greyOverlay = document.getElementById('grey-overlay');
  const mainContent = document.getElementById('main-content');

  // Step 1: Wait a bit, then turn 8 to Infinity
  setTimeout(() => {
    splashSpinTarget.style.transform = 'rotate(0deg)';

    // Step 2: After rotation, move splash logo to top left
    setTimeout(() => {
      // Get target dimensions (it has opacity: 0 but normal layout)
      const rect = targetSvg.getBoundingClientRect();

      // Update splash logo inline styles to match header location exactly
      splashLogo.style.top = rect.top + 'px';
      splashLogo.style.left = rect.left + 'px';
      splashLogo.style.width = rect.width + 'px';
      splashLogo.style.height = rect.height + 'px';
      // Remove centering translation
      splashLogo.style.transform = 'translate(0, 0)';

      // Fade out grey backdrop, fade in main content
      greyOverlay.style.opacity = '0';
      mainContent.style.opacity = '1';
      mainContent.classList.add('visible');

      // Step 3: Finish handover
      setTimeout(() => {
        splashLogo.style.opacity = '0'; // hide splash
        targetSvg.style.opacity = '1'; // Show actual logo

        // Cleanup DOM
        setTimeout(() => {
          splashLogo.style.display = 'none';
          greyOverlay.style.display = 'none';
        }, 500);
      }, 1000); // Wait for the movement transition (1s)

    }, 1200); // Wait for rotation to be fully appreciated
  }, 600); // Initial stall for 600ms on load
}, 0);
