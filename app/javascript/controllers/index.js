import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
// Lazy, not eager (#681): under importmap (no bundling) eager loading fetched
// and evaluated all 60 controllers on EVERY page — signed-out pages included.
// Lazy loading fetches a controller on the first matching data-controller in
// the DOM; the app's own dynamic imports (cropperjs) already follow this.
lazyLoadControllersFrom("controllers", application)

import BiscuitController from "biscuit/biscuit_controller"
application.register("biscuit", BiscuitController)
