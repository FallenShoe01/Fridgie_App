import 'package:openfoodfacts/openfoodfacts.dart';

// ── OFF Environment ───────────────────────────────────────────────────────────
// Product lookups: choose ONE. Swap the comment to switch environments.

// STAGING — world.openfoodfacts.net (test server, safe for development).
 const UriProductHelper kOffLookupUriHelper = uriHelperFoodTest;

// PRODUCTION — world.openfoodfacts.org (live server).
// Uncomment and comment out the staging line above when releasing.
// const UriProductHelper kOffLookupUriHelper = uriHelperFoodProd;

// Auth (login / register): always production.
//
// The staging server's /cgi/auth.pl returns a null JSON body (HTTP 200) which
// causes the SDK to crash. Real OFF accounts live on production anyway.
const UriProductHelper kOffAuthUriHelper = uriHelperFoodProd;

// ─────────────────────────────────────────────────────────────────────────────
