// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// Register biscuit-rails GDPR cookie consent controller
import BiscuitController from "biscuit/biscuit_controller"
application.register("biscuit", BiscuitController)
