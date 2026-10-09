'use strict';
/* ---------------------------------------------------------------------------
   DATABASE_URL -> the separate fields pg.Client / pg.Pool accept.

   pg's own connection-string parser does not decode every percent-escape in
   the password: a Supabase password containing '#' (written %23 in the URL)
   reached the server still encoded and failed authentication. Decoding the
   parts here and passing them as fields avoids that. SSL is configured by the
   caller (DATABASE_SSL), so query options like ?sslmode= are not needed.
   --------------------------------------------------------------------------- */

/* A stray '%' that is not an escape must not crash the server at boot. */
function decode(s) {
  try { return decodeURIComponent(s); } catch (e) { return s; }
}

function connectionParams(url) {
  var u;
  try { u = new URL(url); } catch (e) { return { connectionString: url }; }
  return {
    host: u.hostname,
    port: u.port ? Number(u.port) : 5432,
    user: decode(u.username),
    password: decode(u.password),
    database: decode(u.pathname.replace(/^\//, '')) || 'postgres'
  };
}

module.exports = connectionParams;
