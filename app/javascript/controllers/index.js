import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

import BiscuitController from "biscuit/biscuit_controller"
application.register("biscuit", BiscuitController)
