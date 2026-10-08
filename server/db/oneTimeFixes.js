'use strict';
/* ---------------------------------------------------------------------------
   Data changes that must run once against whichever database the server is
   pointed at — chiefly the live one on Vercel, which has no terminal to run
   a script from.

   Each fix is recorded in app_one_time_fixes inside the same transaction as
   its changes, so it runs exactly once even with several instances starting
   together, and never again after that: re-enabling someone or changing a
   password later is not undone on the next cold start.

   The first /api request waits for this; a failure is logged and the request
   carries on, so a bad fix can never take sign-in down.
   --------------------------------------------------------------------------- */

var db = require('./pool');
var config = require('../config/env');
var passwords = require('../services/passwordService');

var FIXES = [
  {
    /* Admin EXE replaces Husen (Super Admin), Manish and Rutvik, who are deleted. */
    key: '2026-10-admin-exe-delete-old',
    run: function (client) {
      var old = ['husen', 'manish', 'rutvik'];
      /* No password is written in the code: the account starts on the site's
         DEFAULT_PASSWORD and must choose its own at first sign-in. */
      return passwords.hash(config.password.defaultPassword).then(function (hash) {
        /* Deleting cascades to their credentials and sessions; their
           checklist records keep the entry with user_id set to null. */
        return client.query('delete from app_users where uid = any($1)', [old])
          .then(function () {
            return client.query("update app_users set role = 'exec', updated_at = now() where role = 'superadmin' and uid <> 'adminexe'");
          })
          .then(function () {
            return client.query(
              "insert into app_users (id, uid, name, role, loc, first_login, must_change_password, created_by, pending, disabled) " +
              "values ('U-ADMEXE', 'adminexe', 'Admin EXE', 'superadmin', null, true, true, 'fix', false, false) " +
              "on conflict (uid) do update set role = 'superadmin', loc = null, pending = false, disabled = false, " +
              "  must_change_password = true, updated_at = now() " +
              'returning id');
          })
          .then(function (r) {
            var id = r.rows[0].id;
            return client.query(
              'insert into app_user_credentials (user_id, password_hash) values ($1, $2) ' +
              'on conflict (user_id) do update set password_hash = excluded.password_hash, ' +
              '  password_updated_at = now(), failed_attempts = 0, locked_until = null',
              [id, hash]);
          });
      });
    }
  }
];

function runOne(fix) {
  return db.transaction(function (client) {
    return client.query(
      'insert into app_one_time_fixes (key) values ($1) on conflict (key) do nothing returning key', [fix.key]
    ).then(function (r) {
      if (!r.rows[0]) return false;
      return fix.run(client).then(function () { return true; });
    });
  }).then(function (ran) {
    if (ran) console.log('[fixes] applied ' + fix.key);
  });
}

function runAll() {
  return db.query('create table if not exists app_one_time_fixes (key text primary key, done_at timestamptz not null default now())')
    .then(function () {
      return FIXES.reduce(function (chain, fix) {
        return chain.then(function () { return runOne(fix); });
      }, Promise.resolve());
    });
}

var pending = null;
function ready() {
  if (!pending) {
    pending = runAll().catch(function (err) {
      console.error('[fixes] FAILED:', err.message);
      pending = null;            /* try again on the next request */
    });
  }
  return pending;
}

module.exports = { ready: ready };
