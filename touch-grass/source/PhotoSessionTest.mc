import Toybox.Lang;
import Toybox.Test;

(:test)
function photoVerificationContract(logger) {
    var pending = {"status" => "_pending".substring(1, 8), "confidence" => null, "threshold" => 0.7, "expiresInS" => 600};
    Test.assert(PhotoSession.validStatus(pending));
    Test.assert(!PhotoSession.isPassed(pending));
    pending["confidence"] = 0.99;
    Test.assert(!PhotoSession.isPassed(pending));
    pending["status"] = "_passed".substring(1, 7);
    pending["confidence"] = 0.699;
    Test.assert(!PhotoSession.isPassed(pending));
    pending["confidence"] = 0.70;
    Test.assert(PhotoSession.isPassed(pending));
    pending["confidence"] = null;
    Test.assert(!PhotoSession.isPassed(pending));
    pending["confidence"] = "0.99";
    Test.assert(!PhotoSession.isPassed(pending));
    pending["confidence"] = 1.01;
    Test.assert(!PhotoSession.isPassed(pending));
    pending["confidence"] = 0.99;
    pending["threshold"] = 0.6;
    Test.assert(!PhotoSession.isPassed(pending));
    Test.assert(!PhotoSession.isPassed({"error" => {"code" => "SESSION_EXPIRED"}}));
    Test.assert(!PhotoSession.isPassed(null));

    var rows = [] as Array<String>;
    for (var row = 0; row < 21; row += 1) { rows.add("000000000000000000000"); }
    var creation = {"id" => "abcdefghijkl_-12", "url" => "https://example.com/photo/abcdefghijkl_-12", "qr" => rows, "expiresInS" => 600};
    Test.assert(PhotoSession.validCreation(creation));
    rows[0] = "00000000000000000000X";
    Test.assert(!PhotoSession.validCreation(creation));
    rows[0] = "0";
    Test.assert(!PhotoSession.validCreation(creation));
    rows[0] = "000000000000000000000";
    creation["id"] = "../../../../oops";
    Test.assert(!PhotoSession.validCreation(creation));
    creation["id"] = "abcdefghijkl_-12";
    creation["expiresInS"] = 0;
    Test.assert(!PhotoSession.validCreation(creation));

    // Cancelled/hidden attempts cannot accept even a well-formed late pass.
    var session = new PhotoSession();
    session.stop();
    pending["threshold"] = 0.7;
    session.onResponse(200, pending, [0, false]);
    Test.assert(session.qr == null);
    Test.assert(session.status.equals("loading"));
    // START never walks through PROVE_IT, nor does a hidden success callback.
    var app = getApp();
    var originalState = app.flowState;
    app.viewHidden();
    app.flowState = PROVE_IT;
    app.advanceFlow();
    Test.assert(app.flowState == PROVE_IT);
    app.photoPassed();
    Test.assert(app.flowState == PROVE_IT);
    // Verification reveals the animated challenge without starting its timer.
    app.flowState = MAP;
    app.viewShown();
    app.flowState = PROVE_IT;
    app.photoPassed();
    Test.assert(app.flowState == TOUCH_GRASS);
    Test.assert(app.touchProgress() == null);
    app.onRedraw();
    Test.assert(app.touchProgress() == null);
    app.advanceFlow();
    Test.assert(app.flowState == TOUCH_GRASS);
    Test.assert(app.touchProgress() != null);
    app.onStop(null);
    app.flowState = originalState;
    return true;
}
