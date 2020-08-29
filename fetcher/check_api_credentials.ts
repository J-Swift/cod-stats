const API = require('call-of-duty-api')();

const USERNAME = process.env.COD_USERNAME;
const PASSWORD = process.env.COD_PASSWORD;

// DO WORK SON

/*
 * CLI handler
 */

(async () => {
  if (!USERNAME) {
    console.error('Must set envvar [COD_USERNAME]');
    process.exit(1);
  }

  if (!PASSWORD) {
    console.error('Must set envvar [COD_PASSWORD]');
    process.exit(1);
  }

  try {
    await API.login(USERNAME, PASSWORD);
    console.log('Credentials valid.');
  } catch (err) {
    console.log('--------------------------------------------------------------------------------');
    console.error('ERROR:');
    console.error(err);
    process.exit(1);
  }
})();
