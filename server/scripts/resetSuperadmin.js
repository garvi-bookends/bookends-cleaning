'use strict';
/* ---------------------------------------------------------------------------
   Sets the Super Admin's password — the way back in when the Super Admin is
   locked out, since nobody else can reset that account from the app.

     SUPERADMIN_RESET_PASSWORD=<password> npm run reset-superadmin

   On Vercel, scripts/build.js runs this during the deployment whenever
   SUPERADMIN_RESET_PASSWORD is set, because the database is only reachable
   from there. Set it, deploy once, sign in, then DELETE the variable —
   otherwise every deployment sets the password back.

   The password is not forced to change, the lockout and the sign-in rate
   limit are cleared, and every existing session is signed out. The password
   itself is never printed.
   --------------------------------------------------------------------------- */

var db = require('../db/pool');
var userModel = require('../models/userModel');
var passwords = require('../services/passwordService');
var refreshTokens = require('../models/refreshTokenModel');

var plain = process.env.SUPERADMIN_RESET_PASSWORD || '';

if (!plain) {
  console.error('\nUsage:  SUPERADMIN_RESET_PASSWORD=<password> npm run reset-superadmin\n');
  process.exit(1);
}

db.query("select id, uid, name from app_users where role = 'superadmin'")
  .then(function (r) {
    var u = r.rows[0];
    if (!u) throw new Error('there is no Super Admin account (npm run set-superadmin -- <uid>)');
    return passwords.hash(plain)
      .then(function (hash) { return userModel.setPasswordHash(u.id, hash, false); })
      .then(function () { return refreshTokens.revokeAllForUser(u.id); })
      .then(function () { return db.query('delete from app_rate_limits where key ilike $1', ['%' + u.uid + '%']); })
      .then(function () {
        console.log('[reset-superadmin] password set for ' + u.uid + ' (' + u.name + '); lockout cleared, sessions signed out');
      });
  })
  .then(function () { return db.close(); })
  .then(function () { process.exit(0); })
  .catch(function (err) {
    console.error('[reset-superadmin] failed: ' + err.message);
    return db.close().then(function () { process.exit(1); }, function () { process.exit(1); });
  });
