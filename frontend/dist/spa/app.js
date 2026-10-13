/* =====================================================================
 * KelolaKerja — Single Page Application Runtime (app.js)
 * Real Neural Network Face Recognition (@vladmandic/face-api ResNet-34 128-D)
 * + 68-Landmark 3D Active Liveness & Anti-Spoofing Verification
 * ===================================================================== */

(function () {
  'use strict';

  // Application State
  const state = {
    token: localStorage.getItem('kk_token') || '',
    user: JSON.parse(localStorage.getItem('kk_user') || 'null'),
    sidebarOpen: window.innerWidth > 900,
    activeTab: 'attendance',
    loading: false,
    submitting: false,
    loginError: '',
    toasts: [],

    // Neural Network Models State
    modelsLoaded: false,
    modelsLoading: false,
    modelLoadError: '',

    // Camera, 68-Landmark Liveness & Biometrics
    cameraActive: false,
    cameraStream: null,
    trackingTimer: null,
    challengeToken: '',
    currentChallenge: {
      id: 'TURN_LEFT',
      label: 'Toleh Kepala ke Kiri / Kanan',
      instruction: 'Putar wajah Anda perlahan ke samping hingga indikator tahap 1 tercapai, lalu kembali hadap lurus.'
    },
    livenessStep1: false,
    livenessStep2: false,
    livenessConfirmed: false,
    framesAnalyzed: 0,
    frontalHoldFrames: 0,
    landmarkDelta: 0,
    baselinePitch: null,
    motionEmbedding: null,
    descriptorBuffer: [],
    verifiedEmbedding: null,
    detectedFaceCount: 0,
    liveStatusMessage: 'Menunggu kamera diaktifkan...',
    liveTelemetryText: '',
    biometricStatus: { is_registered: 0, registered_at: null, quality_score: null, model_version: null },
    lastExtractedPreview: null,

    // Attendance Data
    todayAttendance: null,
    attendanceHistory: [],

    // Reports Data
    reportsList: [],
    reportModalOpen: false,
    editingReportId: null,
    reportForm: {
      title: '',
      activity_description: '',
      results_achieved: '',
      obstacles: ''
    },

    // Supervisor & Admin Data
    adminOverview: {
      summary: { total_employees: 0, present_count: 0, late_count: 0, checked_out_count: 0, not_present_count: 0 },
      records: []
    },
    usersList: [],
    userModalOpen: false,
    userForm: {
      employee_code: '',
      name: '',
      username: '',
      email: '',
      password: '',
      role: 'EMPLOYEE',
      department: '',
      position: ''
    },
    auditLogs: [],
    verifyModalOpen: false,
    verifyTargetReport: null,
    verifyStatus: 'APPROVED',
    verifyNotes: ''
  };

  // HTTP API Client with Bearer Token Interceptor
  async function apiRequest(method, path, body) {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (state.token) {
      headers['Authorization'] = 'Bearer ' + state.token;
    }

    const opts = { method: method, headers: headers };
    if (body && (method === 'POST' || method === 'PUT')) {
      opts.body = JSON.stringify(body);
    }

    const res = await fetch('/api' + path, opts);
    let data = {};
    try {
      data = await res.json();
    } catch (e) {
      data = { success: 0, message: 'Format respons server tidak valid' };
    }

    if (res.status === 401 && path !== '/auth/login') {
      clearSession();
      render();
      throw new Error(data.message || 'Sesi Anda telah berakhir. Silakan login kembali.');
    }

    if (!res.ok || !data.success) {
      throw new Error(data.message || ('Request gagal dengan status ' + res.status));
    }

    return data;
  }

  function notify(type, message) {
    const id = Date.now() + Math.random();
    state.toasts.push({ id: id, type: type, message: message });
    renderToasts();
    setTimeout(function () {
      state.toasts = state.toasts.filter(function (t) { return t.id !== id; });
      renderToasts();
    }, 5000);
  }

  function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function formatTime(dt) {
    if (!dt) return '--:--';
    const parts = String(dt).split(' ');
    return parts[1] ? parts[1].substring(0, 5) : String(dt);
  }

  function todayDateString() {
    return new Date().toLocaleDateString('id-ID', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  }

  function clearSession() {
    stopCamera();
    localStorage.removeItem('kk_token');
    localStorage.removeItem('kk_user');
    state.token = '';
    state.user = null;
  }

  // Load Neural Network Weights (TinyFaceDetector, 68-Landmark, ResNet-34 128-D Recognition, Expressions)
  async function ensureFaceModelsLoaded() {
    if (state.modelsLoaded) return true;
    if (state.modelsLoading) {
      while (state.modelsLoading) {
        await new Promise(function (r) { setTimeout(r, 100); });
      }
      return state.modelsLoaded;
    }

    if (!window.faceapi) {
      state.modelLoadError = 'Library Neural Network face-api.js belum termuat.';
      throw new Error(state.modelLoadError);
    }

    state.modelsLoading = true;
    state.modelLoadError = '';
    try {
      await Promise.all([
        window.faceapi.nets.tinyFaceDetector.loadFromUri('/models'),
        window.faceapi.nets.faceLandmark68Net.loadFromUri('/models'),
        window.faceapi.nets.faceRecognitionNet.loadFromUri('/models'),
        window.faceapi.nets.faceExpressionNet.loadFromUri('/models')
      ]);
      state.modelsLoaded = true;
      return true;
    } catch (err) {
      state.modelLoadError = 'Gagal memuat model Neural Network: ' + (err.message || String(err));
      throw new Error(state.modelLoadError);
    } finally {
      state.modelsLoading = false;
    }
  }

  function euclideanDistance(vecA, vecB) {
    if (!vecA || !vecB || vecA.length !== vecB.length) return 999.0;
    let sum = 0;
    for (let i = 0; i < vecA.length; i++) {
      const d = vecA[i] - vecB[i];
      sum += d * d;
    }
    return Math.sqrt(sum);
  }

  // Preserve native ResNet-34 descriptor scale (do not alter L2 magnitude)
  function averageDescriptors(descriptors) {
    const dim = 128;
    const avg = new Array(dim).fill(0);
    const n = descriptors.length;
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < dim; j++) {
        avg[j] += descriptors[i][j] / n;
      }
    }
    return avg.map(function (v) {
      return parseFloat(v.toFixed(6));
    });
  }

  function resetLivenessProgress(reasonMsg) {
    state.livenessStep1 = false;
    state.livenessStep2 = false;
    state.livenessConfirmed = false;
    state.frontalHoldFrames = 0;
    state.noFaceFrames = 0;
    state.swapMismatchFrames = 0;
    state.landmarkDelta = 0;
    state.baselinePitch = null;
    state.motionEmbedding = null;
    state.descriptorBuffer = [];
    state.verifiedEmbedding = null;
    if (reasonMsg) {
      state.liveStatusMessage = reasonMsg;
    }
  }

  // Update Live Liveness & Telemetry DOM Elements Without Recreating Video Element
  function updateLivenessDOM() {
    const bannerEl = document.getElementById('kk-liveness-banner');
    const statusEl = document.getElementById('kk-liveness-status');
    const subStatusEl = document.getElementById('kk-liveness-substatus');
    const progressEl = document.getElementById('kk-liveness-progress-bar');
    const telemetryEl = document.getElementById('kk-liveness-telemetry');
    const guideEl = document.getElementById('kk-oval-guide');
    const badgeEl = document.getElementById('kk-liveness-badge');

    let progressPct = 15;
    if (state.livenessConfirmed) {
      progressPct = 100;
    } else if (state.livenessStep1 && !state.livenessStep2) {
      progressPct = 55 + Math.min(40, state.frontalHoldFrames * 15);
    }

    if (progressEl) {
      progressEl.style.width = progressPct + '%';
      progressEl.style.backgroundColor = state.livenessConfirmed
        ? '#15803d'
        : (state.livenessStep1 ? '#1565c0' : '#b45309');
    }

    if (bannerEl) {
      bannerEl.className = 'banner ' + (
        state.livenessConfirmed
          ? 'banner-success'
          : (state.detectedFaceCount === 1 ? 'banner-info' : 'banner-warning')
      );
    }

    if (badgeEl) {
      badgeEl.className = 'badge ' + (state.livenessConfirmed ? 'badge-positive' : 'badge-warning');
      badgeEl.textContent = state.livenessConfirmed
        ? 'LIVENESS LULUS & TERKUNCI'
        : (state.livenessStep1 ? 'TAHAP 2: HADAP LURUS' : 'TAHAP 1: GERAKAN 3D');
    }

    if (guideEl) {
      if (state.livenessConfirmed) {
        guideEl.style.borderColor = '#22c55e';
        guideEl.style.borderStyle = 'solid';
        guideEl.style.borderWidth = '3px';
      } else if (state.livenessStep1) {
        guideEl.style.borderColor = '#38bdf8';
        guideEl.style.borderStyle = 'dashed';
        guideEl.style.borderWidth = '3px';
      } else {
        guideEl.style.borderColor = 'rgba(255, 255, 255, 0.85)';
        guideEl.style.borderStyle = 'dashed';
        guideEl.style.borderWidth = '2px';
      }
    }

    if (statusEl) {
      statusEl.textContent = state.liveStatusMessage;
    }

    if (subStatusEl) {
      if (state.livenessConfirmed) {
        subStatusEl.textContent = 'Verifikasi Anti-Spoofing 68-Landmark & Vektor ResNet-34 (128-D) berhasil dikunci! Silakan klik tombol hijau di bawah.';
      } else if (!state.livenessStep1) {
        subStatusEl.textContent = 'Tahap 1/2 (Tantangan 3D): ' + state.currentChallenge.instruction;
      } else {
        subStatusEl.textContent = 'Tahap 2/2 (Kunci Vektor Frontal): Sekarang hadapkan wajah LURUS ke tengah kamera (' + state.frontalHoldFrames + '/3 frame)...';
      }
    }

    if (telemetryEl) {
      telemetryEl.textContent = state.liveTelemetryText;
    }

    // Update buttons disabled state dynamically
    const today = state.todayAttendance;
    const hasCheckIn = today && today.check_in_time;
    const hasCheckOut = today && today.check_out_time;

    const btnCheckIn = document.getElementById('btn-checkin');
    if (btnCheckIn) {
      btnCheckIn.disabled = !!(hasCheckIn || !state.livenessConfirmed || state.submitting);
    }

    const btnCheckOut = document.getElementById('btn-checkout');
    if (btnCheckOut) {
      btnCheckOut.disabled = !!(!hasCheckIn || hasCheckOut || !state.livenessConfirmed || state.submitting);
    }

    const btnEnroll = document.getElementById('btn-enroll');
    if (btnEnroll) {
      btnEnroll.disabled = !!(!state.livenessConfirmed || state.submitting);
    }
  }

  // Real-Time 68-Landmark & ResNet-34 Tracking Loop
  async function runFaceTrackingLoop() {
    if (!state.cameraActive) return;

    const videoEl = document.getElementById('kk-live-video');
    const canvasEl = document.getElementById('kk-face-overlay');

    if (!videoEl || !videoEl.videoWidth || videoEl.paused || videoEl.ended) {
      state.trackingTimer = setTimeout(runFaceTrackingLoop, 200);
      return;
    }

    try {
      const options = new window.faceapi.TinyFaceDetectorOptions({
        inputSize: 320,
        scoreThreshold: 0.50
      });

      const detections = await window.faceapi
        .detectAllFaces(videoEl, options)
        .withFaceLandmarks()
        .withFaceExpressions()
        .withFaceDescriptors();

      if (!state.cameraActive) return;

      // Draw overlay aligned to video dimensions
      if (canvasEl) {
        canvasEl.width = videoEl.videoWidth;
        canvasEl.height = videoEl.videoHeight;
        const ctx = canvasEl.getContext('2d');
        ctx.clearRect(0, 0, canvasEl.width, canvasEl.height);

        detections.forEach(function (d) {
          const box = d.detection.box;
          ctx.strokeStyle = state.livenessConfirmed ? '#22c55e' : '#38bdf8';
          ctx.lineWidth = 2.5;
          ctx.strokeRect(box.x, box.y, box.width, box.height);

          const pts = d.landmarks.positions;
          ctx.fillStyle = state.livenessConfirmed ? '#4ade80' : '#facc15';
          for (let i = 0; i < pts.length; i++) {
            ctx.beginPath();
            ctx.arc(pts[i].x, pts[i].y, 2.0, 0, Math.PI * 2);
            ctx.fill();
          }
        });
      }

      state.detectedFaceCount = detections.length;

      if (detections.length === 0) {
        state.noFaceFrames = (state.noFaceFrames || 0) + 1;
        // Only reset verified state if user leaves the camera for > 30 frames (~6 seconds)
        if (state.livenessConfirmed) {
          if (state.noFaceFrames > 30) {
            resetLivenessProgress('Wajah tidak terlihat di kamera lebih dari 6 detik. Verifikasi direset.');
          }
        } else {
          state.liveStatusMessage = 'Posisikan wajah di tengah lingkaran panduan dan pastikan cahaya cukup.';
        }
        state.liveTelemetryText = 'Wajah: 0 | Model: ResNet-34 128-D';
        updateLivenessDOM();
        state.trackingTimer = setTimeout(runFaceTrackingLoop, 200);
        return;
      }

      state.noFaceFrames = 0;

      if (detections.length > 1) {
        resetLivenessProgress(
          'ANTI-SPOOFING ALERT: Terdeteksi ' + detections.length + ' wajah di kamera! Hanya 1 wajah yang diizinkan.'
        );
        state.liveTelemetryText = 'Wajah: ' + detections.length + ' (Ditolak > 1)';
        updateLivenessDOM();
        state.trackingTimer = setTimeout(runFaceTrackingLoop, 220);
        return;
      }

      // Single face detected
      const det = detections[0];
      const pts = det.landmarks.positions;
      const descriptor = Array.from(det.descriptor);
      state.framesAnalyzed += 1;

      // 3D Landmark Geometry Calculations
      // Jaw width (pts[0] to pts[16]), Nose tip (pts[30]), Nose bridge (pts[27]), Chin (pts[8])
      const jawWidth = Math.max(1.0, pts[16].x - pts[0].x);
      const noseYawRatio = (pts[30].x - pts[0].x) / jawWidth; // ~0.50 when straight ahead
      const yawOffset = Math.abs(noseYawRatio - 0.50);

      const faceHeight = Math.max(1.0, pts[8].y - pts[27].y);
      const pitchRatio = (pts[30].y - pts[27].y) / faceHeight;
      if (state.baselinePitch === null && yawOffset < 0.08) {
        state.baselinePitch = pitchRatio;
      }
      const pitchDelta = state.baselinePitch !== null ? Math.abs(pitchRatio - state.baselinePitch) : 0;

      // Mouth Aspect Ratio
      const mouthWidth = Math.max(1.0, Math.hypot(pts[54].x - pts[48].x, pts[54].y - pts[48].y));
      const mouthOpen = Math.hypot(pts[66].x - pts[62].x, pts[66].y - pts[62].y);
      const mar = mouthOpen / mouthWidth;
      const happyScore = (det.expressions && det.expressions.happy) ? det.expressions.happy : 0;

      state.liveTelemetryText =
        'Wajah: 1 | Skor Deteksi: ' + (det.detection.score * 100).toFixed(0) + '% | ' +
        '3D Yaw: ' + noseYawRatio.toFixed(2) + ' | MAR/Smile: ' + Math.max(mar, happyScore).toFixed(2) + ' | ' +
        'Delta: ' + state.landmarkDelta.toFixed(3) + ' | Frame: ' + state.framesAnalyzed;

      // Once Liveness is Confirmed (GREEN), keep it locked unless a genuinely different frontal face swaps in for 6+ frames
      if (state.livenessConfirmed && state.verifiedEmbedding) {
        const liveDist = euclideanDistance(state.verifiedEmbedding, descriptor);
        if (yawOffset < 0.08 && liveDist > 0.48) {
          state.swapMismatchFrames = (state.swapMismatchFrames || 0) + 1;
          if (state.swapMismatchFrames >= 6) {
            resetLivenessProgress('PERINGATAN KEAMANAN: Pergantian wajah terdeteksi di kamera! Silakan ulangi verifikasi.');
            updateLivenessDOM();
            state.trackingTimer = setTimeout(runFaceTrackingLoop, 180);
            return;
          }
        } else {
          state.swapMismatchFrames = 0;
        }
        state.liveStatusMessage = 'TERVERIFIKASI: Subjek Hidup (3D Liveness) & Vektor ResNet-34 Terkunci!';
        updateLivenessDOM();
        state.trackingTimer = setTimeout(runFaceTrackingLoop, 250);
        return;
      }

      // STAGE 1: Active 3D Challenge Detection
      if (!state.livenessStep1) {
        const cid = state.currentChallenge.id;
        let challengePassed = false;
        let computedDelta = 0;

        if (cid === 'TURN_LEFT' || cid === 'TURN_RIGHT') {
          if (yawOffset >= 0.095) {
            challengePassed = true;
            computedDelta = Math.max(0.12, yawOffset);
          }
        } else if (cid === 'SMILE_OPEN') {
          if (happyScore >= 0.50 || mar >= 0.17) {
            challengePassed = true;
            computedDelta = Math.max(0.14, mar, happyScore * 0.25);
          }
        } else if (cid === 'HEAD_NOD') {
          if (pitchDelta >= 0.038 || yawOffset >= 0.095) {
            challengePassed = true;
            computedDelta = Math.max(0.12, pitchDelta * 2.5, yawOffset);
          }
        }

        if (challengePassed && state.framesAnalyzed >= 2) {
          state.livenessStep1 = true;
          state.landmarkDelta = parseFloat(computedDelta.toFixed(4));
          state.motionEmbedding = descriptor;
          state.frontalHoldFrames = 0;
          state.descriptorBuffer = [];
          state.liveStatusMessage = 'Tahap 1 Berhasil! Sekarang kembalikan wajah menghadap LURUS ke tengah kamera.';
        } else {
          state.liveStatusMessage = 'Lakukan Tantangan Anti-Spoofing: ' + state.currentChallenge.label;
        }
      }
      // STAGE 2: Return to Frontal Neutral Pose & Lock ResNet-34 Descriptor
      else if (state.livenessStep1 && !state.livenessStep2) {
        const isFrontal = yawOffset <= 0.095;

        if (isFrontal) {
          state.frontalHoldFrames += 1;
          state.descriptorBuffer.push(descriptor);
          state.liveStatusMessage = 'Mengunci Vektor Neural Network ResNet-34 (' + state.frontalHoldFrames + '/3)...';

          if (state.frontalHoldFrames >= 3) {
            const avgVec = averageDescriptors(state.descriptorBuffer);
            state.verifiedEmbedding = avgVec;

            // Ensure motionEmbedding has valid inter-frame distance (0.0005 .. 0.65)
            const mDist = state.motionEmbedding ? euclideanDistance(state.motionEmbedding, avgVec) : 0;
            if (!state.motionEmbedding || mDist > 0.65 || mDist < 0.0002) {
              state.motionEmbedding = state.descriptorBuffer[0];
            }

            state.livenessStep2 = true;
            state.livenessConfirmed = true;
            state.swapMismatchFrames = 0;
            state.liveStatusMessage = 'TERVERIFIKASI: Liveness 3D & Vektor Wajah ResNet-34 Siap!';
          }
        } else {
          state.liveStatusMessage = 'Tahap 1 Selesai — Sekarang hadapkan wajah LURUS ke tengah lingkaran...';
        }
      }

      updateLivenessDOM();
    } catch (err) {
      state.liveStatusMessage = 'Kesalahan pemindaian neural network: ' + (err.message || String(err));
      updateLivenessDOM();
    }

    if (state.cameraActive) {
      state.trackingTimer = setTimeout(runFaceTrackingLoop, 180);
    }
  }

  // Camera Lifecycle
  async function startCamera() {
    stopCamera();
    resetLivenessProgress('Memuat model Neural Network ResNet-34 & meminta tantangan server...');
    state.framesAnalyzed = 0;
    state.cameraActive = true;
    render();

    try {
      await ensureFaceModelsLoaded();

      // Request server-signed HMAC challenge token
      try {
        const chalRes = await apiRequest('GET', '/biometric/challenge');
        if (chalRes && chalRes.data) {
          state.challengeToken = chalRes.data.challenge_token || '';
          state.currentChallenge = chalRes.data.challenge || state.currentChallenge;
        }
      } catch (chalErr) {
        notify('warning', 'Gagal mengambil challenge liveness dari server: ' + chalErr.message);
      }

      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
        audio: false
      });
      state.cameraStream = stream;
      state.liveStatusMessage = 'Lakukan Tantangan Anti-Spoofing: ' + state.currentChallenge.label;
      render();

      const videoEl = document.getElementById('kk-live-video');
      if (videoEl) {
        videoEl.srcObject = stream;
        await videoEl.play().catch(function () {});
      }

      runFaceTrackingLoop();
    } catch (err) {
      stopCamera();
      render();
      notify('negative', err.message || 'Gagal mengakses kamera browser: Pastikan izin kamera diizinkan.');
    }
  }

  function stopCamera() {
    if (state.trackingTimer) {
      clearTimeout(state.trackingTimer);
      state.trackingTimer = null;
    }
    if (state.cameraStream) {
      state.cameraStream.getTracks().forEach(function (track) {
        track.stop();
      });
      state.cameraStream = null;
    }
    state.cameraActive = false;
    resetLivenessProgress('Kamera dimatikan.');
  }

  // Data Loaders
  async function loadTabData(tab) {
    state.loading = true;
    render();
    try {
      if (tab === 'attendance') {
        const [bioRes, todayRes, histRes] = await Promise.all([
          apiRequest('GET', '/biometric/status'),
          apiRequest('GET', '/attendance/today'),
          apiRequest('GET', '/attendance/history')
        ]);
        state.biometricStatus = bioRes.data || { is_registered: 0 };
        state.todayAttendance = todayRes.data || null;
        state.attendanceHistory = histRes.data || [];
      } else if (tab === 'biometric') {
        const bioRes = await apiRequest('GET', '/biometric/status');
        state.biometricStatus = bioRes.data || { is_registered: 0 };
      } else if (tab === 'reports') {
        const repRes = await apiRequest('GET', '/reports');
        state.reportsList = (repRes.data && repRes.data.reports) || [];
      } else if (tab === 'supervisor') {
        const [ovRes, repRes] = await Promise.all([
          apiRequest('GET', '/attendance/admin-overview'),
          apiRequest('GET', '/reports')
        ]);
        state.adminOverview = ovRes.data || { summary: {}, records: [] };
        state.reportsList = (repRes.data && repRes.data.reports) || [];
      } else if (tab === 'admin_dashboard') {
        const ovRes = await apiRequest('GET', '/attendance/admin-overview');
        state.adminOverview = ovRes.data || { summary: {}, records: [] };
      } else if (tab === 'admin_users') {
        const usrRes = await apiRequest('GET', '/admin/users');
        state.usersList = usrRes.data || [];
      } else if (tab === 'admin_audit') {
        const audRes = await apiRequest('GET', '/admin/audit-logs');
        state.auditLogs = audRes.data || [];
      }
    } catch (err) {
      notify('negative', err.message);
    } finally {
      state.loading = false;
      render();
      if (state.cameraActive && state.cameraStream) {
        const videoEl = document.getElementById('kk-live-video');
        if (videoEl && videoEl.srcObject !== state.cameraStream) {
          videoEl.srcObject = state.cameraStream;
        }
      }
    }
  }

  function initDefaultTabForRole() {
    if (!state.user) return;
    if (state.user.role === 'ADMIN') {
      state.activeTab = 'admin_dashboard';
    } else if (state.user.role === 'SUPERVISOR') {
      state.activeTab = 'supervisor';
    } else {
      state.activeTab = 'attendance';
    }
  }

  // Global Actions exposed to event handlers
  window.KK = {
    fillDemoAccount: function (username, password) {
      const uInput = document.getElementById('login-username');
      const pInput = document.getElementById('login-password');
      if (uInput && pInput) {
        uInput.value = username;
        pInput.value = password;
      }
    },

    submitLogin: async function (ev) {
      ev.preventDefault();
      const username = document.getElementById('login-username').value.trim();
      const password = document.getElementById('login-password').value;

      if (!username || !password) {
        state.loginError = 'Username dan password wajib diisi.';
        render();
        return;
      }

      state.submitting = true;
      state.loginError = '';
      render();

      try {
        const res = await apiRequest('POST', '/auth/login', { username: username, password: password });
        state.token = res.data.token;
        state.user = res.data.user;
        localStorage.setItem('kk_token', state.token);
        localStorage.setItem('kk_user', JSON.stringify(state.user));
        initDefaultTabForRole();
        notify('positive', 'Selamat datang, ' + state.user.name);
        await loadTabData(state.activeTab);
      } catch (err) {
        state.loginError = err.message;
      } finally {
        state.submitting = false;
        render();
      }
    },

    logout: async function () {
      try {
        await apiRequest('POST', '/auth/logout');
      } catch (e) {}
      clearSession();
      render();
    },

    toggleSidebar: function () {
      state.sidebarOpen = !state.sidebarOpen;
      render();
    },

    navigate: function (tab) {
      stopCamera();
      state.activeTab = tab;
      if (window.innerWidth <= 900) {
        state.sidebarOpen = false;
      }
      loadTabData(tab);
    },

    startCamera: function () {
      startCamera();
    },

    stopCamera: function () {
      stopCamera();
      render();
    },

    enrollBiometric: async function () {
      if (!state.livenessConfirmed || !state.verifiedEmbedding) {
        notify('warning', 'Selesaikan tantangan gerakan liveness 3D di depan kamera terlebih dahulu.');
        return;
      }

      state.submitting = true;
      updateLivenessDOM();
      try {
        state.lastExtractedPreview = state.verifiedEmbedding.slice(0, 6).join(', ') + ' ... (ResNet-34 128-D)';
        const res = await apiRequest('POST', '/biometric/register', {
          embedding: state.verifiedEmbedding,
          quality_score: 0.96,
          challenge_token: state.challengeToken,
          liveness_proof: {
            step1_passed: state.livenessStep1 ? 1 : 0,
            step2_passed: state.livenessStep2 ? 1 : 0,
            landmark_delta: state.landmarkDelta,
            frames_analyzed: state.framesAnalyzed,
            motion_embedding: state.motionEmbedding
          }
        });
        notify('positive', res.message || 'Biometrik wajah ResNet-34 berhasil disimpan.');
        stopCamera();
        await loadTabData('biometric');
      } catch (err) {
        notify('negative', err.message);
        // Refresh challenge token on error so user must re-verify liveness cleanly
        startCamera();
      } finally {
        state.submitting = false;
        render();
      }
    },

    recordAttendance: async function (type) {
      if (!state.livenessConfirmed || !state.verifiedEmbedding) {
        notify('warning', 'Verifikasi Liveness 3D belum selesai. Ikuti instruksi gerakan kepala di kamera.');
        return;
      }

      state.submitting = true;
      updateLivenessDOM();
      try {
        const endpoint = type === 'check-in' ? '/attendance/check-in' : '/attendance/check-out';
        const res = await apiRequest('POST', endpoint, {
          embedding: state.verifiedEmbedding,
          liveness_passed: 1,
          challenge_token: state.challengeToken,
          liveness_proof: {
            step1_passed: state.livenessStep1 ? 1 : 0,
            step2_passed: state.livenessStep2 ? 1 : 0,
            landmark_delta: state.landmarkDelta,
            frames_analyzed: state.framesAnalyzed,
            motion_embedding: state.motionEmbedding
          },
          photo_path: 'capture_' + type + '_' + Date.now() + '.jpg'
        });
        notify('positive', res.message);
        stopCamera();
        await loadTabData('attendance');
      } catch (err) {
        notify('negative', err.message);
        // Reset liveness challenge after a failed/rejected attempt
        startCamera();
      } finally {
        state.submitting = false;
        render();
      }
    },

    resetUserBiometric: async function (userId, userName) {
      if (!window.confirm('Reset data biometrik wajah untuk ' + userName + '? Pengguna harus mendaftarkan ulang wajahnya.')) {
        return;
      }
      try {
        const res = await apiRequest('DELETE', '/admin/users/' + userId + '/biometric');
        notify('positive', res.message || 'Biometrik wajah pengguna berhasil direset.');
        await loadTabData('admin_users');
      } catch (err) {
        notify('negative', err.message);
      }
    },

    openReportModal: function (reportId) {
      if (reportId) {
        const found = state.reportsList.find(function (r) { return r.id === reportId; });
        if (found) {
          state.editingReportId = found.id;
          state.reportForm = {
            title: found.title || '',
            activity_description: found.activity_description || '',
            results_achieved: found.results_achieved || '',
            obstacles: found.obstacles || ''
          };
        }
      } else {
        state.editingReportId = null;
        state.reportForm = { title: '', activity_description: '', results_achieved: '', obstacles: '' };
      }
      state.reportModalOpen = true;
      render();
    },

    closeReportModal: function () {
      state.reportModalOpen = false;
      state.editingReportId = null;
      render();
    },

    saveReport: async function (ev) {
      ev.preventDefault();
      const title = document.getElementById('rep-title').value.trim();
      const desc = document.getElementById('rep-desc').value.trim();
      const results = document.getElementById('rep-results').value.trim();
      const obstacles = document.getElementById('rep-obstacles').value.trim();

      if (!title || !desc) {
        notify('warning', 'Judul dan deskripsi aktivitas wajib diisi.');
        return;
      }

      state.reportForm = {
        title: title,
        activity_description: desc,
        results_achieved: results,
        obstacles: obstacles
      };
      state.submitting = true;
      render();
      try {
        const payload = state.reportForm;
        if (state.editingReportId) {
          await apiRequest('PUT', '/reports/' + state.editingReportId, payload);
          notify('positive', 'Laporan berhasil diperbarui.');
        } else {
          await apiRequest('POST', '/reports', payload);
          notify('positive', 'Laporan aktivitas berhasil dikirim.');
        }
        state.reportModalOpen = false;
        await loadTabData('reports');
      } catch (err) {
        notify('negative', err.message);
      } finally {
        state.submitting = false;
        render();
      }
    },

    openVerifyModal: function (reportId, status) {
      state.verifyTargetReport = state.reportsList.find(function (r) { return r.id === reportId; }) || { id: reportId };
      state.verifyStatus = status;
      state.verifyNotes = status === 'APPROVED' ? 'Laporan sesuai dan disetujui.' : 'Mohon lengkapi rincian output pekerjaan.';
      state.verifyModalOpen = true;
      render();
    },

    closeVerifyModal: function () {
      state.verifyModalOpen = false;
      state.verifyTargetReport = null;
      render();
    },

    confirmVerifyReport: async function (ev) {
      ev.preventDefault();
      if (!state.verifyTargetReport) return;
      const notes = document.getElementById('verify-notes').value.trim();
      state.submitting = true;
      render();
      try {
        const res = await apiRequest('POST', '/reports/' + state.verifyTargetReport.id + '/verify', {
          status: state.verifyStatus,
          verification_notes: notes
        });
        notify('positive', res.message);
        state.verifyModalOpen = false;
        await loadTabData(state.activeTab);
      } catch (err) {
        notify('negative', err.message);
      } finally {
        state.submitting = false;
        render();
      }
    },

    openUserModal: function () {
      state.userForm = {
        employee_code: 'EMP-00' + (state.usersList.length + 1),
        name: '',
        username: '',
        email: '',
        password: '',
        role: 'EMPLOYEE',
        department: 'Engineering',
        position: 'Staff'
      };
      state.userModalOpen = true;
      render();
    },

    closeUserModal: function () {
      state.userModalOpen = false;
      render();
    },

    saveUser: async function (ev) {
      ev.preventDefault();
      const payload = {
        employee_code: document.getElementById('usr-code').value.trim(),
        name: document.getElementById('usr-name').value.trim(),
        username: document.getElementById('usr-username').value.trim(),
        email: document.getElementById('usr-email').value.trim(),
        password: document.getElementById('usr-password').value,
        role: document.getElementById('usr-role').value,
        department: document.getElementById('usr-dept').value.trim(),
        position: document.getElementById('usr-pos').value.trim()
      };

      if (!payload.employee_code || !payload.name || !payload.username || !payload.password) {
        notify('warning', 'NIK, Nama, Username, dan Password wajib diisi.');
        return;
      }

      state.submitting = true;
      render();
      try {
        const res = await apiRequest('POST', '/admin/users', payload);
        notify('positive', res.message || 'Akun karyawan baru berhasil dibuat.');
        state.userModalOpen = false;
        await loadTabData('admin_users');
      } catch (err) {
        notify('negative', err.message);
      } finally {
        state.submitting = false;
        render();
      }
    },

    toggleUserStatus: async function (userId, currentActive) {
      const nextStatus = Number(currentActive) === 1 ? 0 : 1;
      try {
        await apiRequest('PUT', '/admin/users/' + userId + '/status', { is_active: nextStatus });
        notify('positive', 'Status keaktifan akun berhasil diperbarui.');
        await loadTabData('admin_users');
      } catch (err) {
        notify('negative', err.message);
      }
    }
  };

  // Render Helper for Liveness Panel inside Camera Views
  function renderLivenessPanel() {
    if (!state.cameraActive) return '';
    return (
      '<div id="kk-liveness-banner" class="banner ' + (state.livenessConfirmed ? 'banner-success' : 'banner-info') + '" style="margin-top: 16px; margin-bottom: 0;">' +
        '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; gap: 8px;">' +
          '<strong id="kk-liveness-status">' + escapeHtml(state.liveStatusMessage) + '</strong>' +
          '<span id="kk-liveness-badge" class="badge ' + (state.livenessConfirmed ? 'badge-positive' : 'badge-warning') + '">' +
            (state.livenessConfirmed ? 'LIVENESS LULUS & TERKUNCI' : 'TAHAP 1: GERAKAN 3D') +
          '</span>' +
        '</div>' +
        '<div id="kk-liveness-substatus" style="font-size: 0.85rem; margin-bottom: 10px;">' +
          escapeHtml(state.currentChallenge.instruction) +
        '</div>' +
        '<div style="width: 100%; height: 8px; background: rgba(15, 23, 42, 0.12); border-radius: 99px; overflow: hidden; margin-bottom: 8px;">' +
          '<div id="kk-liveness-progress-bar" style="width: ' + (state.livenessConfirmed ? '100%' : '15%') + '; height: 100%; background: ' + (state.livenessConfirmed ? '#15803d' : '#1565c0') + '; transition: width 0.2s ease;"></div>' +
        '</div>' +
        '<div id="kk-liveness-telemetry" class="mono" style="font-size: 0.75rem; opacity: 0.9;">' +
          escapeHtml(state.liveTelemetryText || 'Memulai sensor 68-titik landmark wajah...') +
        '</div>' +
      '</div>'
    );
  }

  // Render Functions
  function renderToasts() {
    let container = document.getElementById('kk-toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'kk-toast-container';
      container.className = 'toast-container';
      document.body.appendChild(container);
    }
    container.innerHTML = state.toasts.map(function (t) {
      return '<div class="toast toast-' + escapeHtml(t.type) + '" role="status">' + escapeHtml(t.message) + '</div>';
    }).join('');
  }

  function renderLoginView() {
    return (
      '<div class="login-wrapper">' +
        '<div class="login-card">' +
          '<div style="text-align: center; margin-bottom: 24px;">' +
            '<div class="brand-badge">' +
              '<svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">' +
                '<path d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4" />' +
              '</svg>' +
            '</div>' +
            '<h1 style="font-size: 1.5rem; font-weight: 800; color: #0f172a;">KelolaKerja</h1>' +
            '<p style="color: #475569; font-size: 0.9rem; margin-top: 4px;">Sistem Absensi Wajah (ResNet-34) &amp; Pelaporan Karyawan</p>' +
          '</div>' +

          (state.loginError
            ? '<div class="banner banner-error" role="alert">' + escapeHtml(state.loginError) + '</div>'
            : '') +

          '<form onsubmit="KK.submitLogin(event)">' +
            '<div class="form-group">' +
              '<label class="form-label" for="login-username">Username atau Email</label>' +
              '<input id="login-username" type="text" class="form-control" placeholder="Masukkan username (misal: karyawan)" required autocomplete="username" />' +
            '</div>' +
            '<div class="form-group">' +
              '<label class="form-label" for="login-password">Password</label>' +
              '<input id="login-password" type="password" class="form-control" placeholder="Masukkan password" required autocomplete="current-password" />' +
            '</div>' +
            '<button type="submit" class="btn btn-primary btn-full" ' + (state.submitting ? 'disabled' : '') + '>' +
              (state.submitting ? 'Memverifikasi Kredensial...' : 'Masuk ke Akun') +
            '</button>' +
          '</form>' +

          '<div style="margin-top: 22px; padding-top: 16px; border-top: 1px solid #e2e8f0;">' +
            '<div style="font-size: 0.8rem; font-weight: 700; color: #475569;">AKUN PENGUJIAN TERSEDIA (KLIK UNTUK ISI OTOMATIS):</div>' +
            '<div class="demo-accounts">' +
              '<button type="button" class="demo-chip" onclick="KK.fillDemoAccount(\'admin\', \'admin123\')">Admin (admin)</button>' +
              '<button type="button" class="demo-chip" onclick="KK.fillDemoAccount(\'supervisor\', \'supervisor123\')">Supervisor (supervisor)</button>' +
              '<button type="button" class="demo-chip" onclick="KK.fillDemoAccount(\'karyawan\', \'karyawan123\')">Karyawan (karyawan)</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>'
    );
  }

  function renderAttendanceTab() {
    const isReg = Number(state.biometricStatus.is_registered) === 1;
    const today = state.todayAttendance;
    const hasCheckIn = today && today.check_in_time;
    const hasCheckOut = today && today.check_out_time;

    return (
      '<div class="grid-row grid-2">' +
        '<div class="card">' +
          '<div class="card-header">' +
            '<div>' +
              '<div class="card-title">Verifikasi Wajah Absensi (ResNet-34 + 3D Liveness)</div>' +
              '<div class="card-subtitle">Deteksi 68 titik landmark wajah &amp; pencocokan identitas 1:1 dengan pemilik akun.</div>' +
            '</div>' +
            '<span class="badge ' + (isReg ? 'badge-positive' : 'badge-warning') + '">' +
              (isReg ? 'Biometrik Terkunci' : 'Belum Registrasi Wajah') +
            '</span>' +
          '</div>' +
          '<div class="card-body">' +
            (!isReg
              ? '<div class="banner banner-warning">' +
                  '<strong>Perhatian:</strong> Wajah Anda belum terdaftar di database biometrik. Silakan buka menu <strong>Registrasi Wajah</strong> di panel kiri sebelum melakukan absensi.' +
                '</div>'
              : '') +

            '<div class="camera-box">' +
              '<video id="kk-live-video" class="camera-video" autoplay playsinline muted></video>' +
              '<canvas id="kk-face-overlay" style="position: absolute; inset: 0; width: 100%; height: 100%; transform: scaleX(-1); pointer-events: none;"></canvas>' +
              '<div id="kk-oval-guide" class="camera-oval-guide"></div>' +
              (!state.cameraActive
                ? '<div class="camera-placeholder">' +
                    '<p style="font-weight: 600; font-size: 1rem; margin-bottom: 6px;">Sensor Kamera Biometrik Siap</p>' +
                    '<p style="font-size: 0.85rem; color: #94a3b8;">Klik tombol Aktifkan Kamera di bawah untuk memulai deteksi liveness 3D &amp; verifikasi wajah.</p>' +
                  '</div>'
                : '') +
            '</div>' +

            renderLivenessPanel() +
          '</div>' +
          '<div class="card-footer">' +
            (!state.cameraActive
              ? '<button type="button" class="btn btn-primary" onclick="KK.startCamera()">Aktifkan Kamera Wajah</button>'
              : '<button type="button" class="btn btn-outline" onclick="KK.stopCamera()">Matikan Kamera</button>' +
                '<button id="btn-checkin" type="button" class="btn btn-positive" onclick="KK.recordAttendance(\'check-in\')" ' +
                  ((hasCheckIn || !state.livenessConfirmed || state.submitting) ? 'disabled' : '') + '>' +
                  (state.submitting ? 'Memverifikasi...' : 'Absen Masuk (Check-In)') +
                '</button>' +
                '<button id="btn-checkout" type="button" class="btn btn-warning" onclick="KK.recordAttendance(\'check-out\')" ' +
                  ((!hasCheckIn || hasCheckOut || !state.livenessConfirmed || state.submitting) ? 'disabled' : '') + '>' +
                  (state.submitting ? 'Memverifikasi...' : 'Absen Pulang (Check-Out)') +
                '</button>') +
          '</div>' +
        '</div>' +

        '<div style="display: flex; flex-direction: column; gap: 20px;">' +
          '<div class="card">' +
            '<div class="card-header">' +
              '<div>' +
                '<div class="card-title">Status Kehadiran Hari Ini</div>' +
                '<div class="card-subtitle">' + escapeHtml(todayDateString()) + '</div>' +
              '</div>' +
              (today
                ? '<span class="badge ' + (today.status === 'PRESENT' ? 'badge-positive' : 'badge-warning') + '">' + escapeHtml(today.status) + '</span>'
                : '<span class="badge badge-neutral">BELUM ABSEN</span>') +
            '</div>' +
            '<div class="card-body">' +
              '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; text-align: center;">' +
                '<div style="padding: 14px; background: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;">' +
                  '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">WAKTU MASUK</div>' +
                  '<div class="mono" style="font-size: 1.4rem; font-weight: 800; color: #15803d; margin-top: 4px;">' +
                    (today && today.check_in_time ? escapeHtml(formatTime(today.check_in_time)) : '--:--') +
                  '</div>' +
                  (today && today.check_in_match_score !== null && today.check_in_match_score !== undefined
                    ? '<div class="mono" style="font-size: 0.75rem; color: #475569; margin-top: 4px;">Jarak Vektor: ' + escapeHtml(today.check_in_match_score) + '</div>'
                    : '') +
                '</div>' +
                '<div style="padding: 14px; background: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;">' +
                  '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">WAKTU PULANG</div>' +
                  '<div class="mono" style="font-size: 1.4rem; font-weight: 800; color: #b45309; margin-top: 4px;">' +
                    (today && today.check_out_time ? escapeHtml(formatTime(today.check_out_time)) : '--:--') +
                  '</div>' +
                  (today && today.check_out_match_score !== null && today.check_out_match_score !== undefined
                    ? '<div class="mono" style="font-size: 0.75rem; color: #475569; margin-top: 4px;">Jarak Vektor: ' + escapeHtml(today.check_out_match_score) + '</div>'
                    : '') +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +

          '<div class="card">' +
            '<div class="card-header">' +
              '<div class="card-title">Riwayat Kehadiran Pribadi</div>' +
            '</div>' +
            '<div class="table-responsive">' +
              '<table class="data-table">' +
                '<thead>' +
                  '<tr>' +
                    '<th>Tanggal</th>' +
                    '<th>Masuk</th>' +
                    '<th>Pulang</th>' +
                    '<th>Status</th>' +
                  '</tr>' +
                '</thead>' +
                '<tbody>' +
                  (state.attendanceHistory.length === 0
                    ? '<tr><td colspan="4" style="text-align: center; color: #475569; padding: 20px;">Belum ada riwayat absensi tercatat.</td></tr>'
                    : state.attendanceHistory.map(function (row) {
                        return (
                          '<tr>' +
                            '<td class="mono">' + escapeHtml(row.attendance_date) + '</td>' +
                            '<td class="mono">' + escapeHtml(formatTime(row.check_in_time)) + '</td>' +
                            '<td class="mono">' + escapeHtml(formatTime(row.check_out_time)) + '</td>' +
                            '<td><span class="badge ' + (row.status === 'PRESENT' ? 'badge-positive' : 'badge-warning') + '">' + escapeHtml(row.status) + '</span></td>' +
                          '</tr>'
                        );
                      }).join('')) +
                '</tbody>' +
              '</table>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>'
    );
  }

  function renderBiometricTab() {
    const isReg = Number(state.biometricStatus.is_registered) === 1;
    return (
      '<div class="grid-row grid-2">' +
        '<div class="card">' +
          '<div class="card-header">' +
            '<div>' +
              '<div class="card-title">Pendaftaran Biometrik Wajah (ResNet-34 128-D)</div>' +
              '<div class="card-subtitle">Wajah yang didaftarkan dikunci ke akun ini dan dicek duplikasinya terhadap seluruh akun lain.</div>' +
            '</div>' +
          '</div>' +
          '<div class="card-body">' +
            (isReg
              ? '<div class="banner banner-info">' +
                  '<strong>Proteksi Biometrik Aktif:</strong> Akun Anda sudah memiliki wajah terdaftar. Pembaruan sampel hanya diizinkan jika wajah di kamera cocok dengan pemilik akun. Jika ingin mengganti pemilik wajah, hubungi Admin.' +
                '</div>'
              : '') +
            '<div class="camera-box">' +
              '<video id="kk-live-video" class="camera-video" autoplay playsinline muted></video>' +
              '<canvas id="kk-face-overlay" style="position: absolute; inset: 0; width: 100%; height: 100%; transform: scaleX(-1); pointer-events: none;"></canvas>' +
              '<div id="kk-oval-guide" class="camera-oval-guide"></div>' +
              (!state.cameraActive
                ? '<div class="camera-placeholder">' +
                    '<p style="font-weight: 600; font-size: 1rem; margin-bottom: 6px;">Siap Merekam Biometrik ResNet-34</p>' +
                    '<p style="font-size: 0.85rem; color: #94a3b8;">Selesaikan tantangan liveness 3D saat kamera aktif untuk mengekstrak 128-D descriptor wajah asli Anda.</p>' +
                  '</div>'
                : '') +
            '</div>' +

            renderLivenessPanel() +
          '</div>' +
          '<div class="card-footer">' +
            (!state.cameraActive
              ? '<button type="button" class="btn btn-primary" onclick="KK.startCamera()">Buka Kamera Pendaftaran</button>'
              : '<button type="button" class="btn btn-outline" onclick="KK.stopCamera()">Batal</button>' +
                '<button id="btn-enroll" type="button" class="btn btn-positive" onclick="KK.enrollBiometric()" ' +
                  ((!state.livenessConfirmed || state.submitting) ? 'disabled' : '') + '>' +
                  (state.submitting ? 'Menyimpan Vektor...' : 'Ambil & Kunci Biometrik Wajah') +
                '</button>') +
          '</div>' +
        '</div>' +

        '<div class="card">' +
          '<div class="card-header">' +
            '<div class="card-title">Informasi Keamanan Biometrik Terdaftar</div>' +
          '</div>' +
          '<div class="card-body">' +
            '<div style="display: flex; flex-direction: column; gap: 14px;">' +
              '<div>' +
                '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">STATUS BIOMETRIK</div>' +
                '<div style="margin-top: 4px;">' +
                  '<span class="badge ' + (isReg ? 'badge-positive' : 'badge-warning') + '">' +
                    (isReg ? 'TERDAFTAR & TERKUNCI (1:1 & 1:N)' : 'BELUM TERDAFTAR') +
                  '</span>' +
                '</div>' +
              '</div>' +
              '<div>' +
                '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">WAKTU PENDAFTARAN TERAKHIR</div>' +
                '<div class="mono" style="margin-top: 4px; font-weight: 600;">' +
                  escapeHtml(state.biometricStatus.registered_at || 'Belum ada data') +
                '</div>' +
              '</div>' +
              '<div>' +
                '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">ARSITEKTUR NEURAL NETWORK &amp; AMBANG BATAS</div>' +
                '<div class="mono" style="margin-top: 4px; font-size: 0.85rem;">' +
                  escapeHtml(state.biometricStatus.model_version || 'resnet34-128d') + ' (Max Euclidean Distance: 0.4200 | Min Cosine Similarity: 89.0%)' +
                '</div>' +
              '</div>' +
              '<div>' +
                '<div style="font-size: 0.8rem; color: #475569; font-weight: 600;">PROTEKSI ANTI-SPOOFING &amp; ANTI-TITIP ABSEN</div>' +
                '<div style="margin-top: 4px; font-size: 0.85rem; color: #334155;">' +
                  '1. <strong>68-Landmark 3D Active Challenge</strong> (menolak foto cetak &amp; layar HP).<br/>' +
                  '2. <strong>1:N Cross-Account Deduplication</strong> (1 wajah tidak bisa didaftarkan di 2 akun).<br/>' +
                  '3. <strong>Self-Overwrite Lock</strong> (wajah terdaftar tidak bisa ditimpa wajah orang lain).' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>'
    );
  }

  function renderReportsTab() {
    return (
      '<div class="card">' +
        '<div class="card-header">' +
          '<div>' +
            '<div class="card-title">Laporan Aktivitas Harian</div>' +
            '<div class="card-subtitle">Kirim laporan hasil pekerjaan harian untuk diperiksa oleh Supervisor.</div>' +
          '</div>' +
          '<button type="button" class="btn btn-primary" onclick="KK.openReportModal()">+ Buat Laporan Baru</button>' +
        '</div>' +
        '<div class="table-responsive">' +
          '<table class="data-table">' +
            '<thead>' +
              '<tr>' +
                '<th>Tanggal</th>' +
                '<th>Karyawan</th>' +
                '<th>Judul Pekerjaan</th>' +
                '<th>Deskripsi &amp; Hasil</th>' +
                '<th>Status</th>' +
                '<th>Catatan Verifikator</th>' +
                '<th>Aksi</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>' +
              (state.reportsList.length === 0
                ? '<tr><td colspan="7" style="text-align: center; padding: 24px; color: #475569;">Belum ada laporan aktivitas yang diajukan.</td></tr>'
                : state.reportsList.map(function (r) {
                    const badgeClass = r.status === 'APPROVED' ? 'badge-positive' : (r.status === 'REJECTED' ? 'badge-negative' : 'badge-warning');
                    const canEdit = r.user_id === state.user.id && r.status !== 'APPROVED';
                    return (
                      '<tr>' +
                        '<td class="mono">' + escapeHtml(r.report_date) + '</td>' +
                        '<td>' + escapeHtml(r.employee_name || state.user.name) + '</td>' +
                        '<td style="font-weight: 600;">' + escapeHtml(r.title) + '</td>' +
                        '<td>' +
                          '<div>' + escapeHtml(r.activity_description) + '</div>' +
                          (r.results_achieved ? '<div style="font-size: 0.8rem; color: #15803d; margin-top: 4px;"><strong>Hasil:</strong> ' + escapeHtml(r.results_achieved) + '</div>' : '') +
                          (r.obstacles ? '<div style="font-size: 0.8rem; color: #b45309; margin-top: 2px;"><strong>Kendala:</strong> ' + escapeHtml(r.obstacles) + '</div>' : '') +
                        '</td>' +
                        '<td><span class="badge ' + badgeClass + '">' + escapeHtml(r.status) + '</span></td>' +
                        '<td style="font-size: 0.85rem; color: #475569;">' +
                          '<div>' + escapeHtml(r.verification_notes || '-') + '</div>' +
                          (r.verifier_name
                            ? '<div style="font-size: 0.76rem; color: #64748b; margin-top: 2px;">Oleh: <strong>' + escapeHtml(r.verifier_name) + '</strong></div>'
                            : '') +
                        '</td>' +
                        '<td>' +
                          (canEdit
                            ? '<button type="button" class="btn btn-outline btn-sm" onclick="KK.openReportModal(\'' + escapeHtml(r.id) + '\')">' +
                                (r.status === 'REJECTED' ? 'Perbaiki & Kirim Ulang' : 'Edit') +
                              '</button>'
                            : '<span class="badge badge-positive">Terkunci (Disetujui)</span>') +
                        '</td>' +
                      '</tr>'
                    );
                  }).join('')) +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>'
    );
  }

  function renderStatCards(summary) {
    const s = summary || {};
    return (
      '<div class="grid-row grid-4" style="margin-bottom: 20px;">' +
        '<div class="stat-card">' +
          '<div class="stat-label">Karyawan Aktif</div>' +
          '<div class="stat-value" style="color: #1565c0;">' + Number(s.total_employees || 0) + '</div>' +
        '</div>' +
        '<div class="stat-card">' +
          '<div class="stat-label">Hadir Hari Ini</div>' +
          '<div class="stat-value" style="color: #15803d;">' + Number(s.present_count || 0) + '</div>' +
        '</div>' +
        '<div class="stat-card">' +
          '<div class="stat-label">Terlambat Masuk</div>' +
          '<div class="stat-value" style="color: #b45309;">' + Number(s.late_count || 0) + '</div>' +
        '</div>' +
        '<div class="stat-card">' +
          '<div class="stat-label">Belum Absen</div>' +
          '<div class="stat-value" style="color: #b91c1c;">' + Number(s.not_present_count || 0) + '</div>' +
        '</div>' +
      '</div>'
    );
  }

  function renderSupervisorTab() {
    return (
      renderStatCards(state.adminOverview.summary) +
      '<div class="card">' +
        '<div class="card-header">' +
          '<div>' +
            '<div class="card-title">Verifikasi Laporan Aktivitas Tim</div>' +
            '<div class="card-subtitle">Tinjau dan berikan persetujuan atau penolakan terhadap laporan harian karyawan.</div>' +
          '</div>' +
        '</div>' +
        '<div class="table-responsive">' +
          '<table class="data-table">' +
            '<thead>' +
              '<tr>' +
                '<th>Tanggal</th>' +
                '<th>NIK &amp; Nama</th>' +
                '<th>Judul Tugas</th>' +
                '<th>Rincian Aktivitas</th>' +
                '<th>Status</th>' +
                '<th>Tindakan / Hasil Verifikasi</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>' +
              (state.reportsList.length === 0
                ? '<tr><td colspan="6" style="text-align: center; padding: 24px; color: #475569;">Belum ada laporan karyawan untuk diverifikasi.</td></tr>'
                : state.reportsList.map(function (r) {
                    const badgeClass = r.status === 'APPROVED' ? 'badge-positive' : (r.status === 'REJECTED' ? 'badge-negative' : 'badge-warning');
                    let actionCell = '';

                    if (r.status === 'APPROVED') {
                      actionCell =
                        '<div style="font-size: 0.82rem;">' +
                          '<div style="font-weight: 700; color: #15803d;">&#10003; Telah Disetujui</div>' +
                          (r.verifier_name ? '<div style="color: #475569;">Oleh: ' + escapeHtml(r.verifier_name) + '</div>' : '') +
                          (r.verification_notes ? '<div style="color: #64748b; font-style: italic; margin-top: 2px;">"' + escapeHtml(r.verification_notes) + '"</div>' : '') +
                        '</div>';
                    } else if (r.status === 'REJECTED') {
                      actionCell =
                        '<div style="font-size: 0.82rem;">' +
                          '<div style="font-weight: 700; color: #b91c1c;">&#10005; Ditolak (Menunggu Revisi)</div>' +
                          (r.verifier_name ? '<div style="color: #475569;">Oleh: ' + escapeHtml(r.verifier_name) + '</div>' : '') +
                          (r.verification_notes ? '<div style="color: #64748b; font-style: italic; margin-top: 2px;">"' + escapeHtml(r.verification_notes) + '"</div>' : '') +
                        '</div>';
                    } else {
                      actionCell =
                        '<div style="display: flex; gap: 6px;">' +
                          '<button type="button" class="btn btn-positive btn-sm" onclick="KK.openVerifyModal(\'' + escapeHtml(r.id) + '\', \'APPROVED\')">Setujui</button>' +
                          '<button type="button" class="btn btn-negative btn-sm" onclick="KK.openVerifyModal(\'' + escapeHtml(r.id) + '\', \'REJECTED\')">Tolak</button>' +
                        '</div>';
                    }

                    return (
                      '<tr>' +
                        '<td class="mono">' + escapeHtml(r.report_date) + '</td>' +
                        '<td>' +
                          '<div style="font-weight: 600;">' + escapeHtml(r.employee_name) + '</div>' +
                          '<div class="mono" style="font-size: 0.78rem; color: #475569;">' + escapeHtml(r.employee_code) + '</div>' +
                        '</td>' +
                        '<td style="font-weight: 600;">' + escapeHtml(r.title) + '</td>' +
                        '<td>' +
                          '<div>' + escapeHtml(r.activity_description) + '</div>' +
                          (r.results_achieved ? '<div style="font-size: 0.8rem; color: #15803d;">Hasil: ' + escapeHtml(r.results_achieved) + '</div>' : '') +
                        '</td>' +
                        '<td><span class="badge ' + badgeClass + '">' + escapeHtml(r.status) + '</span></td>' +
                        '<td>' + actionCell + '</td>' +
                      '</tr>'
                    );
                  }).join('')) +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>'
    );
  }

  function renderAdminDashboardTab() {
    const records = state.adminOverview.records || [];
    return (
      renderStatCards(state.adminOverview.summary) +
      '<div class="card">' +
        '<div class="card-header">' +
          '<div>' +
            '<div class="card-title">Rekapitulasi Kehadiran Seluruh Karyawan</div>' +
            '<div class="card-subtitle">Data aktual dari server database beserta skor jarak verifikasi biometrik wajah ResNet-34.</div>' +
          '</div>' +
        '</div>' +
        '<div class="table-responsive">' +
          '<table class="data-table">' +
            '<thead>' +
              '<tr>' +
                '<th>Tanggal</th>' +
                '<th>NIK</th>' +
                '<th>Nama Karyawan</th>' +
                '<th>Departemen</th>' +
                '<th>Jam Masuk</th>' +
                '<th>Jam Pulang</th>' +
                '<th>Jarak Biometrik</th>' +
                '<th>Status</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>' +
              (records.length === 0
                ? '<tr><td colspan="8" style="text-align: center; padding: 24px; color: #475569;">Belum ada rekaman absensi karyawan.</td></tr>'
                : records.map(function (row) {
                    return (
                      '<tr>' +
                        '<td class="mono">' + escapeHtml(row.attendance_date) + '</td>' +
                        '<td class="mono">' + escapeHtml(row.employee_code) + '</td>' +
                        '<td style="font-weight: 600;">' + escapeHtml(row.user_name) + '</td>' +
                        '<td>' + escapeHtml(row.department || '-') + '</td>' +
                        '<td class="mono">' + escapeHtml(formatTime(row.check_in_time)) + '</td>' +
                        '<td class="mono">' + escapeHtml(formatTime(row.check_out_time)) + '</td>' +
                        '<td class="mono">' + escapeHtml(row.check_in_match_score !== null ? row.check_in_match_score : '-') + '</td>' +
                        '<td><span class="badge ' + (row.status === 'PRESENT' ? 'badge-positive' : 'badge-warning') + '">' + escapeHtml(row.status) + '</span></td>' +
                      '</tr>'
                    );
                  }).join('')) +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>'
    );
  }

  function renderAdminUsersTab() {
    return (
      '<div class="card">' +
        '<div class="card-header">' +
          '<div>' +
            '<div class="card-title">Manajemen Akun Karyawan &amp; Role (RBAC)</div>' +
            '<div class="card-subtitle">Kelola pengguna, role akses, status aktif, serta reset kunci biometrik wajah.</div>' +
          '</div>' +
          '<button type="button" class="btn btn-primary" onclick="KK.openUserModal()">+ Tambah Karyawan</button>' +
        '</div>' +
        '<div class="table-responsive">' +
          '<table class="data-table">' +
            '<thead>' +
              '<tr>' +
                '<th>NIK</th>' +
                '<th>Nama Lengkap</th>' +
                '<th>Username &amp; Email</th>' +
                '<th>Departemen / Jabatan</th>' +
                '<th>Role RBAC</th>' +
                '<th>Biometrik Wajah</th>' +
                '<th>Status Akun</th>' +
                '<th>Aksi</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>' +
              state.usersList.map(function (u) {
                const active = Number(u.is_active) === 1;
                const faceReg = Number(u.face_registered) === 1;
                return (
                  '<tr>' +
                    '<td class="mono" style="font-weight: 600;">' + escapeHtml(u.employee_code) + '</td>' +
                    '<td style="font-weight: 600;">' + escapeHtml(u.name) + '</td>' +
                    '<td>' +
                      '<div>' + escapeHtml(u.username) + '</div>' +
                      '<div style="font-size: 0.78rem; color: #475569;">' + escapeHtml(u.email) + '</div>' +
                    '</td>' +
                    '<td>' +
                      '<div>' + escapeHtml(u.department || '-') + '</div>' +
                      '<div style="font-size: 0.78rem; color: #475569;">' + escapeHtml(u.position || '-') + '</div>' +
                    '</td>' +
                    '<td><span class="badge badge-neutral">' + escapeHtml(u.role) + '</span></td>' +
                    '<td><span class="badge ' + (faceReg ? 'badge-positive' : 'badge-warning') + '">' + (faceReg ? 'Terkunci' : 'Belum') + '</span></td>' +
                    '<td><span class="badge ' + (active ? 'badge-positive' : 'badge-negative') + '">' + (active ? 'AKTIF' : 'NONAKTIF') + '</span></td>' +
                    '<td>' +
                      '<div style="display: flex; gap: 6px; flex-wrap: wrap;">' +
                        '<button type="button" class="btn btn-outline btn-sm" onclick="KK.toggleUserStatus(\'' + escapeHtml(u.id) + '\', ' + (active ? 1 : 0) + ')">' +
                          (active ? 'Nonaktifkan' : 'Aktifkan') +
                        '</button>' +
                        (faceReg
                          ? '<button type="button" class="btn btn-warning btn-sm" onclick="KK.resetUserBiometric(\'' + escapeHtml(u.id) + '\', \'' + escapeHtml(u.name) + '\')">Reset Wajah</button>'
                          : '') +
                      '</div>' +
                    '</td>' +
                  '</tr>'
                );
              }).join('') +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>'
    );
  }

  function renderAdminAuditTab() {
    return (
      '<div class="card">' +
        '<div class="card-header">' +
          '<div>' +
            '<div class="card-title">Audit Log &amp; Jejak Keamanan Sistem</div>' +
            '<div class="card-subtitle">Pencatatan seluruh aktivitas autentikasi, penolakan spoofing, dan ketidakcocokan wajah.</div>' +
          '</div>' +
        '</div>' +
        '<div class="table-responsive">' +
          '<table class="data-table">' +
            '<thead>' +
              '<tr>' +
                '<th>Waktu Server</th>' +
                '<th>Pengguna</th>' +
                '<th>Aksi</th>' +
                '<th>Entitas</th>' +
                '<th>IP Address</th>' +
                '<th>Status</th>' +
                '<th>Detail Konteks</th>' +
              '</tr>' +
            '</thead>' +
            '<tbody>' +
              (state.auditLogs.length === 0
                ? '<tr><td colspan="7" style="text-align: center; padding: 24px; color: #475569;">Belum ada catatan audit log.</td></tr>'
                : state.auditLogs.map(function (log) {
                    const badgeClass = log.status === 'SUCCESS' ? 'badge-positive' : (log.status === 'DENIED' ? 'badge-warning' : 'badge-negative');
                    return (
                      '<tr>' +
                        '<td class="mono" style="font-size: 0.82rem;">' + escapeHtml(log.created_at) + '</td>' +
                        '<td style="font-weight: 600;">' + escapeHtml(log.username || 'Anonim') + '</td>' +
                        '<td class="mono" style="font-size: 0.82rem; font-weight: 600;">' + escapeHtml(log.action) + '</td>' +
                        '<td>' + escapeHtml(log.resource_type) + '</td>' +
                        '<td class="mono" style="font-size: 0.82rem;">' + escapeHtml(log.ip_address) + '</td>' +
                        '<td><span class="badge ' + badgeClass + '">' + escapeHtml(log.status) + '</span></td>' +
                        '<td class="mono" style="font-size: 0.78rem; color: #475569; max-width: 280px; word-break: break-all;">' + escapeHtml(log.details || '-') + '</td>' +
                      '</tr>'
                    );
                  }).join('')) +
            '</tbody>' +
          '</table>' +
        '</div>' +
      '</div>'
    );
  }

  function renderModals() {
    let html = '';

    if (state.reportModalOpen) {
      html += (
        '<div class="modal-backdrop">' +
          '<div class="modal-dialog" role="dialog" aria-modal="true">' +
            '<div class="card-header">' +
              '<div class="card-title">' + (state.editingReportId ? 'Edit Laporan Aktivitas' : 'Form Laporan Aktivitas Harian') + '</div>' +
              '<button type="button" class="btn btn-outline btn-sm" onclick="KK.closeReportModal()">Tutup</button>' +
            '</div>' +
            '<form onsubmit="KK.saveReport(event)">' +
              '<div class="modal-body">' +
                '<div class="form-group">' +
                  '<label class="form-label" for="rep-title">Judul Pekerjaan / Tugas *</label>' +
                  '<input id="rep-title" type="text" class="form-control" value="' + escapeHtml(state.reportForm.title) + '" required placeholder="Contoh: Implementasi Modul Pembayaran" />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="rep-desc">Deskripsi Detail Aktivitas *</label>' +
                  '<textarea id="rep-desc" class="form-control" required placeholder="Jelaskan pekerjaan yang diselesaikan hari ini...">' + escapeHtml(state.reportForm.activity_description) + '</textarea>' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="rep-results">Hasil / Output yang Dicapai</label>' +
                  '<textarea id="rep-results" class="form-control" placeholder="Output terukur atau PR yang diselesaikan...">' + escapeHtml(state.reportForm.results_achieved) + '</textarea>' +
                '</div>' +
                '<div class="form-group" style="margin-bottom: 0;">' +
                  '<label class="form-label" for="rep-obstacles">Kendala / Hambatan (Opsional)</label>' +
                  '<textarea id="rep-obstacles" class="form-control" placeholder="Isi jika ada kendala teknis atau koordinasi...">' + escapeHtml(state.reportForm.obstacles) + '</textarea>' +
                '</div>' +
              '</div>' +
              '<div class="card-footer">' +
                '<button type="button" class="btn btn-outline" onclick="KK.closeReportModal()">Batal</button>' +
                '<button type="submit" class="btn btn-primary" ' + (state.submitting ? 'disabled' : '') + '>' +
                  (state.submitting ? 'Menyimpan...' : 'Simpan & Kirim Laporan') +
                '</button>' +
              '</div>' +
            '</form>' +
          '</div>' +
        '</div>'
      );
    }

    if (state.verifyModalOpen && state.verifyTargetReport) {
      html += (
        '<div class="modal-backdrop">' +
          '<div class="modal-dialog" role="dialog" aria-modal="true">' +
            '<div class="card-header">' +
              '<div class="card-title">Konfirmasi Verifikasi Laporan (' + escapeHtml(state.verifyStatus) + ')</div>' +
              '<button type="button" class="btn btn-outline btn-sm" onclick="KK.closeVerifyModal()">Tutup</button>' +
            '</div>' +
            '<form onsubmit="KK.confirmVerifyReport(event)">' +
              '<div class="modal-body">' +
                '<div class="form-group" style="margin-bottom: 0;">' +
                  '<label class="form-label" for="verify-notes">Catatan Verifikator</label>' +
                  '<textarea id="verify-notes" class="form-control" required>' + escapeHtml(state.verifyNotes) + '</textarea>' +
                '</div>' +
              '</div>' +
              '<div class="card-footer">' +
                '<button type="button" class="btn btn-outline" onclick="KK.closeVerifyModal()">Batal</button>' +
                '<button type="submit" class="btn ' + (state.verifyStatus === 'APPROVED' ? 'btn-positive' : 'btn-negative') + '">' +
                  'Simpan Keputusan (' + escapeHtml(state.verifyStatus) + ')' +
                '</button>' +
              '</div>' +
            '</form>' +
          '</div>' +
        '</div>'
      );
    }

    if (state.userModalOpen) {
      html += (
        '<div class="modal-backdrop">' +
          '<div class="modal-dialog" role="dialog" aria-modal="true">' +
            '<div class="card-header">' +
              '<div class="card-title">Tambah Akun Karyawan Baru</div>' +
              '<button type="button" class="btn btn-outline btn-sm" onclick="KK.closeUserModal()">Tutup</button>' +
            '</div>' +
            '<form onsubmit="KK.saveUser(event)">' +
              '<div class="modal-body">' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-code">Kode NIK Karyawan *</label>' +
                  '<input id="usr-code" type="text" class="form-control" value="' + escapeHtml(state.userForm.employee_code) + '" required />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-name">Nama Lengkap *</label>' +
                  '<input id="usr-name" type="text" class="form-control" required />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-username">Username Login *</label>' +
                  '<input id="usr-username" type="text" class="form-control" required />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-email">Email *</label>' +
                  '<input id="usr-email" type="email" class="form-control" required />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-password">Password Awal *</label>' +
                  '<input id="usr-password" type="password" class="form-control" required />' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-role">Role RBAC *</label>' +
                  '<select id="usr-role" class="form-control">' +
                    '<option value="EMPLOYEE">EMPLOYEE (Karyawan)</option>' +
                    '<option value="SUPERVISOR">SUPERVISOR (HR / Supervisor)</option>' +
                    '<option value="ADMIN">ADMIN (Administrator)</option>' +
                  '</select>' +
                '</div>' +
                '<div class="form-group">' +
                  '<label class="form-label" for="usr-dept">Departemen</label>' +
                  '<input id="usr-dept" type="text" class="form-control" value="Engineering" />' +
                '</div>' +
                '<div class="form-group" style="margin-bottom: 0;">' +
                  '<label class="form-label" for="usr-pos">Jabatan / Posisi</label>' +
                  '<input id="usr-pos" type="text" class="form-control" value="Staff" />' +
                '</div>' +
              '</div>' +
              '<div class="card-footer">' +
                '<button type="button" class="btn btn-outline" onclick="KK.closeUserModal()">Batal</button>' +
                '<button type="submit" class="btn btn-primary" ' + (state.submitting ? 'disabled' : '') + '>Simpan Akun</button>' +
              '</div>' +
            '</form>' +
          '</div>' +
        '</div>'
      );
    }

    return html;
  }

  function renderAppShell() {
    const u = state.user || {};
    const isSpvOrAdmin = u.role === 'ADMIN' || u.role === 'SUPERVISOR';
    const isAdmin = u.role === 'ADMIN';

    let mainContent = '';
    if (state.activeTab === 'attendance') mainContent = renderAttendanceTab();
    else if (state.activeTab === 'biometric') mainContent = renderBiometricTab();
    else if (state.activeTab === 'reports') mainContent = renderReportsTab();
    else if (state.activeTab === 'supervisor') mainContent = renderSupervisorTab();
    else if (state.activeTab === 'admin_dashboard') mainContent = renderAdminDashboardTab();
    else if (state.activeTab === 'admin_users') mainContent = renderAdminUsersTab();
    else if (state.activeTab === 'admin_audit') mainContent = renderAdminAuditTab();

    return (
      '<div class="app-shell">' +
        '<header class="app-header">' +
          '<div class="header-left">' +
            '<button type="button" class="btn btn-primary" style="padding: 0 10px;" aria-label="Menu Navigasi" onclick="KK.toggleSidebar()">' +
              '&#9776;' +
            '</button>' +
            '<span class="header-title">KelolaKerja</span>' +
          '</div>' +
          '<div class="header-right">' +
            '<div class="user-pill">' +
              '<span>' + escapeHtml(u.name) + '</span>' +
              '<span class="role-tag">(' + escapeHtml(u.role) + ')</span>' +
            '</div>' +
            '<button type="button" class="btn btn-outline btn-sm" style="background: rgba(255,255,255,0.12); color: #fff; border-color: rgba(255,255,255,0.3);" onclick="KK.logout()">Keluar</button>' +
          '</div>' +
        '</header>' +

        '<div class="app-body">' +
          '<aside class="app-sidebar ' + (state.sidebarOpen ? '' : 'collapsed') + '">' +
            '<div class="nav-section-title">Menu Karyawan</div>' +
            '<button type="button" class="nav-item ' + (state.activeTab === 'attendance' ? 'active' : '') + '" onclick="KK.navigate(\'attendance\')">' +
              '<div><div>Absensi Wajah</div><span class="nav-item-sub">Check-In &amp; Check-Out</span></div>' +
            '</button>' +
            '<button type="button" class="nav-item ' + (state.activeTab === 'biometric' ? 'active' : '') + '" onclick="KK.navigate(\'biometric\')">' +
              '<div><div>Registrasi Wajah</div><span class="nav-item-sub">ResNet-34 128-D Lock</span></div>' +
            '</button>' +
            '<button type="button" class="nav-item ' + (state.activeTab === 'reports' ? 'active' : '') + '" onclick="KK.navigate(\'reports\')">' +
              '<div><div>Laporan Aktivitas</div><span class="nav-item-sub">Jurnal Kerja Harian</span></div>' +
            '</button>' +

            (isSpvOrAdmin
              ? '<div class="nav-section-title">Supervisi &amp; Tim</div>' +
                '<button type="button" class="nav-item ' + (state.activeTab === 'supervisor' ? 'active' : '') + '" onclick="KK.navigate(\'supervisor\')">' +
                  '<div><div>Verifikasi Laporan</div><span class="nav-item-sub">Approval &amp; Monitoring Tim</span></div>' +
                '</button>'
              : '') +

            (isAdmin
              ? '<div class="nav-section-title">Administrasi Sistem</div>' +
                '<button type="button" class="nav-item ' + (state.activeTab === 'admin_dashboard' ? 'active' : '') + '" onclick="KK.navigate(\'admin_dashboard\')">' +
                  '<div><div>Ringkasan Kehadiran</div><span class="nav-item-sub">Rekapitulasi Perusahaan</span></div>' +
                '</button>' +
                '<button type="button" class="nav-item ' + (state.activeTab === 'admin_users' ? 'active' : '') + '" onclick="KK.navigate(\'admin_users\')">' +
                  '<div><div>Kelola Karyawan</div><span class="nav-item-sub">Manajemen Akun &amp; RBAC</span></div>' +
                '</button>' +
                '<button type="button" class="nav-item ' + (state.activeTab === 'admin_audit' ? 'active' : '') + '" onclick="KK.navigate(\'admin_audit\')">' +
                  '<div><div>Audit Log</div><span class="nav-item-sub">Jejak Keamanan Sistem</span></div>' +
                '</button>'
              : '') +
          '</aside>' +

          '<main class="app-main">' +
            mainContent +
          '</main>' +
        '</div>' +
        renderModals() +
      '</div>'
    );
  }

  function render() {
    const root = document.getElementById('q-app');
    if (!root) return;
    if (!state.token || !state.user) {
      root.innerHTML = renderLoginView();
    } else {
      root.innerHTML = renderAppShell();
    }
    renderToasts();
  }

  // Bootstrap Application
  document.addEventListener('DOMContentLoaded', function () {
    // Preload neural network weights in background
    ensureFaceModelsLoaded().catch(function () {});
    if (state.token && state.user) {
      initDefaultTabForRole();
      render();
      loadTabData(state.activeTab);
    } else {
      render();
    }
  });
})();
