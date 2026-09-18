// Pre-load MPQ files from the server directory into Emscripten virtual filesystem
Module['preRun'] = Module['preRun'] || [];

// Mount IDBFS for persistent save files
Module['preRun'].push(function() {
  console.log('Setting up IDBFS for persistent saves...');

  // SDL uses //libsdl/ as the base path for Emscripten
  // Save files are in //libsdl/diasurgical/devilution/
  // Config files (diablo.ini) would be in //libsdl/diasurgical/
  try {
    // Helper function to create directory if it doesn't exist
    function mkdirSafe(path) {
      try {
        // Check if path exists
        var stat = FS.stat(path);
        // If it exists and is a directory, we're good
        if (FS.isDir(stat.mode)) {
          return;
        }
        // If it exists but is not a directory, this is an error
        console.error('Path exists but is not a directory: ' + path);
        return;
      } catch (e) {
        // Path doesn't exist, try to create it
        try {
          FS.mkdir(path);
        } catch (mkdirErr) {
          // Only throw if it's not an "already exists" error
          if (mkdirErr.errno !== 20 && mkdirErr.errno !== 17) {
            throw mkdirErr;
          }
        }
      }
    }

    // Create SDL directory hierarchy if needed
    mkdirSafe('/libsdl');
    mkdirSafe('/libsdl/diasurgical');

    // Mount the diasurgical directory as IDBFS to persist saves AND settings
    FS.mount(IDBFS, {}, '/libsdl/diasurgical');
    console.log('IDBFS mounted successfully at /libsdl/diasurgical');

    // Sync from IndexedDB to memory (load existing saves)
    Module.addRunDependency('syncfs');
    FS.syncfs(true, function(err) {
      if (err) {
        console.error('Error loading saves from IndexedDB:', err);
      } else {
        console.log('Existing saves loaded from IndexedDB');
      }
      Module.removeRunDependency('syncfs');
    });
  } catch (e) {
    console.error('Error setting up IDBFS:', e);
  }
});

// Load MPQ files from the server directory.
// 큰 파일(정품 DIABDAT.MPQ 517MB)을 매번 받지 않도록 브라우저 Cache API 에 저장하고 다음부터는 거기서 읽는다.
// Chromium 은 Cache 항목 하나가 약 128MB 를 넘으면 실패하므로 64MB 조각으로 나눠 저장한다.
// 진행률은 Module.setStatus 로 화면에 보여 준다.
Module['preRun'].push(function() {
  // index.html 에서 Module.mpqFiles 로 덮어쓸 수 있다(재빌드 없이 목록 변경).
  var mpqFiles = Module['mpqFiles'] || [
    'DIABDAT.MPQ',
    'spawn.mpq',
    'fonts.mpq',
  ];
  var CACHE_NAME = 'devilutionx-mpq-v2';
  var CHUNK = 64 * 1024 * 1024;
  if (typeof caches !== 'undefined') caches.delete('devilutionx-mpq-v1').catch(function() {});

  function setStatus(text) {
    if (Module['setStatus']) Module['setStatus'](text);
  }
  function keyFor(filename, part) { return '/__mpqcache/' + filename + '/' + part; }
  function progress(filename, received, total, verb) {
    var mb = (received / 1048576).toFixed(0);
    setStatus(total
      ? filename + ' ' + verb + ' ' + Math.floor(received * 100 / total) + '% (' + mb + '/' + (total / 1048576).toFixed(0) + ' MB)'
      : filename + ' ' + verb + ' ' + mb + ' MB');
  }

  // 캐시에서 읽기: manifest → 조각들을 하나의 버퍼로.
  function readFromCache(cache, filename) {
    return cache.match(keyFor(filename, 'manifest')).then(function(res) {
      if (!res) return null;
      return res.json().then(function(m) {
        var out = new Uint8Array(m.size);
        var offset = 0;
        var i = 0;
        function next() {
          if (i >= m.chunks) return out;
          return cache.match(keyFor(filename, 'chunk-' + i)).then(function(r) {
            if (!r) throw new Error('missing chunk ' + i);
            return r.arrayBuffer();
          }).then(function(buf) {
            out.set(new Uint8Array(buf), offset);
            offset += buf.byteLength;
            i++;
            progress(filename, offset, m.size, '캐시에서 읽는 중');
            return next();
          });
        }
        return next().catch(function(e) {
          console.warn('Cache for ' + filename + ' is broken, will re-download:', e);
          return null;
        });
      });
    });
  }

  // 네트워크에서 스트리밍으로 받으며 64MB 마다 캐시에 조각을 넣는다.
  function readFromNetwork(cache, filename) {
    return fetch(filename).then(function(response) {
      if (!response.ok) return null;   // 서버에 없는 파일(예: 정품 없음)은 조용히 건너뛴다
      var total = parseInt(response.headers.get('Content-Length') || '0', 10);
      if (!response.body || !response.body.getReader) {
        return response.arrayBuffer().then(function(buf) { return new Uint8Array(buf); });
      }
      var reader = response.body.getReader();
      var out = total ? new Uint8Array(total) : null;
      var pieces = [];          // total 을 모를 때만 쓴다
      var pending = [];         // 현재 조각에 쌓인 작은 덩어리들
      var pendingBytes = 0;
      var received = 0;
      var chunkIndex = 0;
      var puts = [];
      var cacheOk = !!cache;
      var lastShown = 0;

      function flushChunk() {
        if (!cacheOk || pendingBytes === 0) return;
        var block = new Uint8Array(pendingBytes);
        var o = 0;
        for (var k = 0; k < pending.length; k++) { block.set(pending[k], o); o += pending[k].length; }
        var idx = chunkIndex++;
        puts.push(cache.put(keyFor(filename, 'chunk-' + idx), new Response(block)).catch(function(e) {
          cacheOk = false;
          console.warn('Could not cache ' + filename + ' chunk ' + idx + ':', e);
        }));
        pending = []; pendingBytes = 0;
      }

      function pump() {
        return reader.read().then(function(result) {
          if (result.done) {
            flushChunk();
            var data = out;
            if (!data) {
              data = new Uint8Array(received);
              var o = 0;
              for (var k = 0; k < pieces.length; k++) { data.set(pieces[k], o); o += pieces[k].length; }
            }
            return Promise.all(puts).then(function() {
              if (!cacheOk) return data;
              return cache.put(keyFor(filename, 'manifest'),
                new Response(JSON.stringify({ size: received, chunks: chunkIndex, chunkSize: CHUNK }),
                  { headers: { 'Content-Type': 'application/json' } })).then(function() { return data; }, function() { return data; });
            });
          }
          var v = result.value;
          if (out) out.set(v, received); else pieces.push(v);
          received += v.length;
          if (cacheOk) {
            // 64MB 경계에 맞춰 자른다
            var off = 0;
            while (off < v.length) {
              var room = CHUNK - pendingBytes;
              var take = Math.min(room, v.length - off);
              pending.push(v.subarray(off, off + take)); pendingBytes += take; off += take;
              if (pendingBytes === CHUNK) flushChunk();
            }
          }
          var now = Date.now();
          if (now - lastShown > 200) { lastShown = now; progress(filename, received, total, '다운로드 중'); }
          return pump();
        });
      }
      return pump();
    });
  }

  function loadOne(filename) {
    var cachePromise = (typeof caches !== 'undefined')
      ? caches.open(CACHE_NAME).catch(function() { return null; })
      : Promise.resolve(null);
    return cachePromise.then(function(cache) {
      var cached = cache ? readFromCache(cache, filename) : Promise.resolve(null);
      return cached.then(function(data) {
        if (data) return { data: data, source: 'cache' };
        return readFromNetwork(cache, filename).then(function(d) { return d ? { data: d, source: 'network' } : null; });
      });
    }).then(function(result) {
      if (!result) return;
      FS.writeFile('/' + filename, result.data);
      console.log('Successfully loaded ' + filename + ' (' + result.source + ', ' + result.data.length + ' bytes)');
    }).catch(function(e) {
      console.warn('Skipping ' + filename + ':', e);
    });
  }

  Module.addRunDependency('loadMPQs');
  // 순서대로(큰 파일부터) 받아야 진행률 표시가 뒤섞이지 않는다.
  mpqFiles.reduce(function(p, f) { return p.then(function() { return loadOne(f); }); }, Promise.resolve())
    .then(function() {
      setStatus('');
      Module.removeRunDependency('loadMPQs');
    });
});

// Track if a sync is in progress to prevent overlapping operations
var syncInProgress = false;

// Expose function to manually save to IndexedDB
Module['saveToIndexedDB'] = function() {
  if (syncInProgress) {
    return;
  }

  syncInProgress = true;
  FS.syncfs(false, function(err) {
    syncInProgress = false;
    if (err) {
      console.error('Error persisting saves to IndexedDB:', err);
    }
  });
};

// Auto-sync to IndexedDB every 30 seconds as a fallback
Module['postRun'] = Module['postRun'] || [];
Module['postRun'].push(function() {
  setInterval(function() {
    if (!syncInProgress) {
      syncInProgress = true;
      FS.syncfs(false, function(err) {
        syncInProgress = false;
        if (err) {
          console.error('Auto-sync error:', err);
        }
      });
    }
  }, 30000);

  // Sync when the page is about to close
  window.addEventListener('beforeunload', function() {
    if (!syncInProgress) {
      FS.syncfs(false, function(err) {
        if (err) console.error('Error syncing on page unload:', err);
      });
    }
  });
});
