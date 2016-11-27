//
//  FoundationExtensionsSpec.swift
//  ReactiveCocoa
//
//  Created by Neil Pankey on 5/22/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import Result
import Nimble
import Quick
import ReactiveCocoa

class FoundationExtensionsSpec: QuickSpec {
	override func spec() {
		describe("NSNotificationCenter.rac_notifications") {
			let center = NotificationCenter.default

			it("should send notifications on the producer") {
				let producer = center.rac_notifications("rac_notifications_test")

				var notif: NSNotification? = nil
				let disposable = producer.startWithNext { notif = $0 }

				center.post(name: NSNotification.Name(rawValue: "some_other_notification"), object: nil)
				expect(notif).to(beNil())

				center.post(name: NSNotification.Name(rawValue: "rac_notifications_test"), object: nil)
				expect(notif?.name) == "rac_notifications_test"

				notif = nil
				disposable.dispose()

				center.post(name: NSNotification.Name(rawValue: "rac_notifications_test"), object: nil)
				expect(notif).to(beNil())
			}

			it("should send Interrupted when the observed object is freed") {
				var observedObject: AnyObject? = NSObject()
				let producer = center.rac_notifications(object: observedObject)
				observedObject = nil

				var interrupted = false
				let disposable = producer.startWithInterrupted {
					interrupted = true
				}
				expect(interrupted) == true

				disposable.dispose()
			}

		}
	}
}
