(() => {
  const hud = document.querySelector('#hud');
  const core = document.querySelector('#core');
  const label = document.querySelector('#state-label');
  const hint = document.querySelector('#hint');
  const caption = document.querySelector('#caption');
  const remoteAudio = document.querySelector('#remote-audio');
  const bars = [...document.querySelectorAll('.visualizer i')];
  const stopButton = document.querySelector('#stop');
  const connectionLabel = document.querySelector('#connection-label');
  const connectionLed = document.querySelector('#connection-led');
  const audioUnlock = document.querySelector('#audio-unlock');

  let peer = null;
  let channel = null;
  let microphone = null;
  let audioContext = null;
  let micAnalyser = null;
  let outputAnalyser = null;
  let meterFrame = 0;
  let muted = false;
  let toastTimer = 0;
  let assistantText = '';
  let serverReady = false;
  let sessionTimer = 0;

  function setState(state, title, subtitle) {
    hud.dataset.state = state;
    label.textContent = title;
    hint.textContent = subtitle;
  }

  function notify(message) {
    const toast = document.querySelector('#toast');
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 4200);
  }

  function setConnected(connected) {
    connectionLabel.textContent = connected ? 'OPENAI REALTIME · CONNECTÉ' : 'VOIX TEMPS RÉEL · HORS LIGNE';
    connectionLed.style.background = connected ? '#77d6a1' : '#78848d';
    connectionLed.style.boxShadow = connected ? '0 0 9px #77d6a1' : 'none';
  }

  async function checkLocalServer() {
    try {
      const response = await fetch('/api/health', { cache: 'no-store' });
      const health = await response.json();
      serverReady = response.ok;
      connectionLabel.textContent = health.apiKeyConfigured ? 'CLÉ API CONFIGURÉE · PRÊT À TESTER' : 'CLÉ API À CONFIGURER';
      connectionLed.style.background = health.apiKeyConfigured ? '#d5b66d' : '#78848d';
      connectionLed.style.boxShadow = health.apiKeyConfigured ? '0 0 9px #d5b66d66' : 'none';
      if (!response.ok) throw new Error('Serveur local indisponible');
    } catch {
      serverReady = false;
      connectionLabel.textContent = 'SERVEUR LOCAL INDISPONIBLE';
      connectionLed.style.background = '#e57f7f';
      connectionLed.style.boxShadow = '0 0 9px #e57f7f66';
    }
  }

  function startMeter(stream) {
    try {
      audioContext = new AudioContext();
      const source = audioContext.createMediaStreamSource(stream);
      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 256;
      source.connect(analyser);
      micAnalyser = analyser;
      const micSamples = new Uint8Array(analyser.fftSize);
      const outputSamples = new Uint8Array(analyser.fftSize);
      const rms = (node, samples) => {
        if (!node) return 0;
        node.getByteTimeDomainData(samples);
        let sum = 0;
        for (const sample of samples) {
          const value = (sample - 128) / 128;
          sum += value * value;
        }
        return Math.sqrt(sum / samples.length);
      };
      const tick = () => {
        const level = Math.max(0, Math.min(1, (Math.max(rms(micAnalyser, micSamples), rms(outputAnalyser, outputSamples)) - 0.012) * 8));
        bars.forEach((bar, index) => {
          const wave = Math.max(0, 1 - Math.abs(index - (bars.length - 1) / 2) / (bars.length / 2));
          bar.style.height = `${3 + level * (5 + wave * 16)}px`;
          bar.style.opacity = `${0.25 + level * 0.75}`;
        });
        core.style.transform = `translate(-50%, -50%) scale(${1 + level * 0.055})`;
        meterFrame = requestAnimationFrame(tick);
      };
      tick();
    } catch {
      bars.forEach(bar => { bar.style.height = '3px'; });
    }
  }

  function stopMeter() {
    cancelAnimationFrame(meterFrame);
    bars.forEach(bar => { bar.style.height = '3px'; bar.style.opacity = ''; });
    core.style.transform = '';
    micAnalyser = null;
    outputAnalyser = null;
    if (audioContext) {
      void audioContext.close().catch(() => {});
      audioContext = null;
    }
  }

  async function connect() {
    if (peer) return;
    if (!serverReady) {
      await checkLocalServer();
      if (!serverReady) {
        notify('Lancez le HUD avec lancer-jarvis.cmd, puis réessayez.');
        return;
      }
    }
    setState('thinking', 'CONNEXION À JARVIS', 'Préparation de la voix temps réel…');
    core.disabled = true;
    try {
      // Request the microphone only after the user's click.
      microphone = await navigator.mediaDevices.getUserMedia({ audio: true });
      startMeter(microphone);

      // The local server returns a short-lived client secret. The permanent API key
      // stays in the server's .env file and is never sent to this page.
      const tokenResponse = await fetch('/api/realtime/session', { method: 'POST' });
      const tokenData = await tokenResponse.json();
      if (!tokenResponse.ok || !tokenData.value) {
        throw new Error(tokenData.error || 'La session vocale n’a pas pu être créée.');
      }

      peer = new RTCPeerConnection();
      peer.ontrack = event => {
        remoteAudio.srcObject = event.streams[0];
        remoteAudio.muted = muted;
        try {
          const outputSource = audioContext?.createMediaStreamSource(event.streams[0]);
          if (outputSource && audioContext) {
            outputAnalyser = audioContext.createAnalyser();
            outputAnalyser.fftSize = 256;
            outputSource.connect(outputAnalyser);
          }
        } catch {}
        void remoteAudio.play().then(() => { audioUnlock.hidden = true; }).catch(() => {
          audioUnlock.hidden = false;
          notify('Le navigateur attend un clic pour autoriser la voix de Jarvis.');
        });
      };
      peer.onconnectionstatechange = () => {
        if (peer && ['failed', 'disconnected', 'closed'].includes(peer.connectionState)) disconnect();
      };
      microphone.getTracks().forEach(track => peer.addTrack(track, microphone));
      channel = peer.createDataChannel('oai-events');
      channel.addEventListener('open', () => {
        setConnected(true);
        setState('listening', 'JE VOUS ÉCOUTE', 'Parlez naturellement ; vous pouvez m’interrompre');
        stopButton.hidden = false;
        clearTimeout(sessionTimer);
        sessionTimer = window.setTimeout(() => {
          disconnect();
          notify('Fin de la session locale (limite de 15 minutes). Vous pouvez relancer Jarvis.');
        }, 15 * 60 * 1000);
      });
      channel.addEventListener('message', onRealtimeEvent);
      channel.addEventListener('error', () => notify('La connexion vocale a rencontré une erreur.'));

      const offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      const answerResponse = await fetch('https://api.openai.com/v1/realtime/calls', {
        method: 'POST',
        body: offer.sdp,
        headers: {
          Authorization: `Bearer ${tokenData.value}`,
          'Content-Type': 'application/sdp',
        },
      });
      if (!answerResponse.ok) {
        throw new Error(`Connexion Realtime refusée (HTTP ${answerResponse.status}).`);
      }
      await peer.setRemoteDescription({ type: 'answer', sdp: await answerResponse.text() });
      core.setAttribute('aria-label', 'Terminer la conversation avec Jarvis');
    } catch (error) {
      disconnect();
      setState('error', 'CONNEXION IMPOSSIBLE', 'Vérifiez la clé API et les autorisations du micro');
      notify(error instanceof Error ? error.message : 'Erreur de connexion à la voix temps réel.');
      setTimeout(() => setState('idle', 'EN VEILLE', 'Cliquez sur le noyau pour réessayer'), 4500);
    } finally {
      core.disabled = false;
    }
  }

  function onRealtimeEvent(event) {
    let data;
    try { data = JSON.parse(event.data); } catch { return; }
    if (data.type === 'error') {
      notify(data.error?.message || 'Erreur de la session vocale.');
      return;
    }
    if (data.type === 'input_audio_buffer.speech_started') {
      assistantText = '';
      caption.textContent = '';
      setState('listening', 'JE VOUS ÉCOUTE', 'Parlez naturellement ; vous pouvez m’interrompre');
    }
    if (data.type === 'response.created') {
      assistantText = '';
      setState('thinking', 'JE RÉFLÉCHIS', 'Je prépare ma réponse…');
    }
    if (data.type === 'response.audio.delta' || data.type === 'response.output_audio.delta') {
      setState('speaking', 'JE VOUS RÉPONDS', 'Vous pouvez m’interrompre en parlant');
    }
    if (data.type === 'response.audio_transcript.delta' || data.type === 'response.output_audio_transcript.delta') {
      assistantText += data.delta || '';
      caption.textContent = assistantText;
    }
    if (data.type === 'response.audio_transcript.done' || data.type === 'response.output_audio_transcript.done') {
      if (data.transcript) caption.textContent = data.transcript;
    }
    if (data.type === 'conversation.item.input_audio_transcription.completed') {
      if (data.transcript) caption.textContent = data.transcript;
    }
    if (data.type === 'response.done') {
      setState('listening', 'JE VOUS ÉCOUTE', 'Parlez naturellement ; vous pouvez m’interrompre');
    }
  }

  function disconnect() {
    clearTimeout(sessionTimer);
    if (channel) { try { channel.close(); } catch {} channel = null; }
    if (peer) { try { peer.close(); } catch {} peer = null; }
    if (microphone) { microphone.getTracks().forEach(track => track.stop()); microphone = null; }
    remoteAudio.srcObject = null;
    audioUnlock.hidden = true;
    stopMeter();
    stopButton.hidden = true;
    setConnected(false);
    core.setAttribute('aria-label', 'Démarrer la conversation avec Jarvis');
    setState('idle', 'EN VEILLE', 'Cliquez sur le noyau pour parler à Jarvis');
  }

  core.addEventListener('click', () => peer ? disconnect() : connect());
  stopButton.addEventListener('click', disconnect);
  document.querySelector('#fullscreen').addEventListener('click', async () => {
    try {
      document.fullscreenElement ? await document.exitFullscreen() : await document.documentElement.requestFullscreen();
    } catch { notify('Le plein écran est indisponible dans ce navigateur.'); }
  });
  document.querySelector('#audio-toggle').addEventListener('click', () => {
    muted = !muted;
    remoteAudio.muted = muted;
    const button = document.querySelector('#audio-toggle');
    button.textContent = muted ? '◌' : '◖';
    button.title = muted ? 'Activer la voix' : 'Couper la voix';
  });
  audioUnlock.addEventListener('click', async () => {
    try {
      await remoteAudio.play();
      audioUnlock.hidden = true;
      notify('Son de Jarvis activé.');
    } catch {
      notify('La lecture reste bloquée par le navigateur. Vérifiez le volume de l’onglet.');
    }
  });
  window.addEventListener('beforeunload', disconnect);
  void checkLocalServer();
  setInterval(() => {
    document.querySelector('#clock').textContent = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' }).format(new Date());
  }, 1000);
})();
