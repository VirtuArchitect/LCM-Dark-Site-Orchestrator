const modeCard = document.querySelector('#mode-card');
const segments = document.querySelectorAll('.segment');

const modes = {
  linux: {
    title: 'Linux web server',
    body: 'Recommended path. Validate nginx or Apache static hosting, permissions, firewall, and the extracted /darksite/ folder.',
  },
  windows: {
    title: 'Windows / IIS web server',
    body: 'Lab or customer-managed path. Validate IIS static downloads, MIME handling, file reachability, and show an explicit unsupported-by-guide warning.',
  },
};

segments.forEach((button) => {
  button.addEventListener('click', () => {
    segments.forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    const mode = modes[button.dataset.mode];
    modeCard.innerHTML = `<h3>${mode.title}</h3><p>${mode.body}</p>`;
  });
});
