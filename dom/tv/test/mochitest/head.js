"use strict";

function setupPrefsAndPermissions(callback) {
  setupPrefs(function() {
      SpecialPowers.pushPermissions([
        {"type":"tv", "allow":1, "context":document}
      ], callback);
  });
}

function setupPrefs(callback) {
  let xhr = new XMLHttpRequest;
  let data;

  xhr.open("GET", "./mock_data.json", false);
  xhr.send(null);
  if (xhr.status == 200) {
    data = xhr.responseText;
  }

  SpecialPowers.pushPrefEnv({"set": [
                              ["dom.tv.enabled", true],
                              ["dom.ignore_webidl_scope_checks", true],
                              ["dom.testing.tv_mock_data", data]
                            ]}, function() {
    callback();
  });
}

function removePrefsAndPermissions(callback) {
  SpecialPowers.popPrefEnv(function() {
    SpecialPowers.popPermissions(callback);
  });
}

function prepareTest(callback) {
  removePrefsAndPermissions(function() {
    setupPrefsAndPermissions(callback);
  });
}
