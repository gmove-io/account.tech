import { initExtensions } from "./init-extensions.js";
import { PackagePublisher } from "./package-publisher.js";

(async () => {
    const packageManager = new PackagePublisher();
    packageManager.loadPackages(process.env.PACKAGES_PATH!);

    const publishSuccess = await packageManager.publishAll();
    if (publishSuccess) {
        await initExtensions();
    }
})();