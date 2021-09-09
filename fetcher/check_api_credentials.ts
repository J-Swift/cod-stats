const API = require('call-of-duty-api')();

const SSO = process.env.COD_SSO;

// DO WORK SON

/*
 * CLI handler
 */

(async () => {
  if (!SSO) {
    console.error('Must set envvar [COD_SSO]');
    process.exit(1);
  }

  try {
    await API.loginWithSSO(SSO);
    console.log('Credentials valid.');
  } catch (err) {
    console.log('--------------------------------------------------------------------------------');
    console.error('ERROR:');
    console.error(err);
    process.exit(1);
  }
})();
