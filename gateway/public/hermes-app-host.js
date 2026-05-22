/**
 * Hermes Mobile App WebView Host SDK
 * Native bridge channel: HermesAppBridge.postMessage(JSON)
 */
(function () {
  'use strict';

  const pending = Object.create(null);
  let nativeReady = false;
  const readyWaiters = [];

  function hasNativeBridge() {
    return typeof window.HermesAppBridge !== 'undefined' &&
      typeof window.HermesAppBridge.postMessage === 'function';
  }

  function call(method, params) {
    return new Promise(function (resolve, reject) {
      if (!hasNativeBridge()) {
        reject(makeError('UNAVAILABLE', 'HermesApp native bridge unavailable'));
        return;
      }
      const id = 'h' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10);
      pending[id] = { resolve: resolve, reject: reject };
      try {
        window.HermesAppBridge.postMessage(JSON.stringify({ id: id, method: method, params: params || {} }));
      } catch (err) {
        delete pending[id];
        reject(makeError('BRIDGE_ERROR', err && err.message ? err.message : String(err)));
      }
    });
  }

  function makeError(code, message) {
    return { ok: false, code: code, message: message || code };
  }

  window.__hermesAppDeliver = function (id, payload) {
    const entry = pending[id];
    if (!entry) return;
    delete pending[id];
    if (payload && payload.ok === false) {
      entry.reject(payload);
      return;
    }
    entry.resolve(payload && payload.ok === true ? payload : Object.assign({ ok: true }, payload || {}));
  };

  window.__hermesAppNativeReady = function (payload) {
    nativeReady = true;
    if (payload && typeof payload === 'object' && payload.capabilities) {
      window.__HERMES_APP_CAPABILITIES__ = payload.capabilities;
      window.__HERMES_APP_SAVE_DESTINATIONS__ = payload.saveDestinations || {};
    } else if (payload && typeof payload === 'object') {
      window.__HERMES_APP_CAPABILITIES__ = payload;
    }
    while (readyWaiters.length) {
      const fn = readyWaiters.shift();
      try { fn(); } catch (_) { /* ignore */ }
    }
  };

  function ready() {
    if (hasNativeBridge() && nativeReady) return Promise.resolve(api);
    if (hasNativeBridge()) {
      return new Promise(function (resolve) {
        readyWaiters.push(function () { resolve(api); });
        setTimeout(function () { resolve(api); }, 2500);
      });
    }
    return Promise.resolve(api);
  }

  const api = {
    get isAvailable() {
      return hasNativeBridge();
    },
    ready: ready,
    get capabilities() {
      return window.__HERMES_APP_CAPABILITIES__ || {};
    },
    getProject: function () {
      return window.__HERMES_PROJECT__ || null;
    },
    getSaveDestinations: function () {
      return window.__HERMES_APP_SAVE_DESTINATIONS__ || {};
    },
    pickImage: function (opts) { return call('pickImage', opts); },
    pickFile: function (opts) { return call('pickFile', opts); },
    pickVideo: function (opts) { return call('pickVideo', opts); },
    uploadBlob: function (opts) { return call('uploadBlob', opts); },
    compressImage: function (opts) { return call('compressImage', opts); },
    saveFile: function (opts) { return call('saveFile', opts); },
    shareFile: function (opts) { return call('shareFile', opts); },
    share: function (opts) { return call('share', opts); },
    toast: function (message) { return call('toast', { message: String(message == null ? '' : message) }); },
    clipboard: {
      readText: function () { return call('clipboard.readText', {}); },
      writeText: function (text) { return call('clipboard.writeText', { text: String(text == null ? '' : text) }); },
    },
    recordAudio: {
      start: function (opts) { return call('recordAudio.start', opts || {}); },
      stop: function () { return call('recordAudio.stop', {}); },
    },
  };

  window.HermesApp = api;
})();
