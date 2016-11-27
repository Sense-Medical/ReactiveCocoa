//
//  SchedulerSpec.swift
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2014-07-13.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
import Nimble
import Quick
@testable
import ReactiveCocoa

class SchedulerSpec: QuickSpec {
	override func spec() {
		describe("ImmediateScheduler") {
			it("should run enqueued actions immediately") {
				var didRun = false
				ImmediateScheduler().schedule {
					didRun = true
				}

				expect(didRun) == true
			}
		}

		describe("UIScheduler") {
			func dispatchSyncInBackground(_ action: () -> Void) {
				let group = DispatchGroup()
				dispatch_group_async(group, DispatchQueue.global(DispatchQueue.GlobalQueuePriority.high, 0), action)
				group.wait(timeout: dispatch_time_t(DispatchTime.distantFuture))
			}

			it("should run actions immediately when on the main thread") {
				let scheduler = UIScheduler()
				var values: [Int] = []
				expect(Thread.isMainThread) == true

				scheduler.schedule {
					values.append(0)
				}

				expect(values) == [ 0 ]

				scheduler.schedule {
					values.append(1)
				}

				scheduler.schedule {
					values.append(2)
				}

				expect(values) == [ 0, 1, 2 ]
			}

			it("should enqueue actions scheduled from the background") {
				let scheduler = UIScheduler()
				var values: [Int] = []

				dispatchSyncInBackground {
					scheduler.schedule {
						expect(NSThread.isMainThread()) == true
						values.append(0)
					}

					return
				}

				expect(values) == []
				expect(values).toEventually(equal([ 0 ]))

				dispatchSyncInBackground {
					scheduler.schedule {
						expect(NSThread.isMainThread()) == true
						values.append(1)
					}

					scheduler.schedule {
						expect(NSThread.isMainThread()) == true
						values.append(2)
					}

					return
				}

				expect(values) == [ 0 ]
				expect(values).toEventually(equal([ 0, 1, 2 ]))
			}

			it("should run actions enqueued from the main thread after those from the background") {
				let scheduler = UIScheduler()
				var values: [Int] = []

				dispatchSyncInBackground {
					scheduler.schedule {
						expect(NSThread.isMainThread()) == true
						values.append(0)
					}

					return
				}

				scheduler.schedule {
					expect(NSThread.isMainThread()) == true
					values.append(1)
				}

				scheduler.schedule {
					expect(NSThread.isMainThread()) == true
					values.append(2)
				}

				expect(values) == []
				expect(values).toEventually(equal([ 0, 1, 2 ]))
			}
		}

		describe("QueueScheduler") {
			it("should run enqueued actions on a global queue") {
				var didRun = false
				let scheduler: QueueScheduler
				if #available(OSX 10.10, *) {
					scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT)
				} else {
					scheduler = QueueScheduler(queue: DispatchQueue.global(DispatchQueue.GlobalQueuePriority.default, 0))
				}
				scheduler.schedule {
					didRun = true
					expect(NSThread.isMainThread()) == false
				}

				expect{didRun}.toEventually(beTruthy())
			}

			describe("on a given queue") {
				var scheduler: QueueScheduler!

				beforeEach {
					if #available(OSX 10.10, *) {
						scheduler = QueueScheduler(qos: QOS_CLASS_DEFAULT)
					} else {
						scheduler = QueueScheduler(queue: DispatchQueue.global(DispatchQueue.GlobalQueuePriority.default, 0))
					}
					scheduler.queue.suspend()
				}

				it("should run enqueued actions serially on the given queue") {
					var value = 0

					for _ in 0..<5 {
						scheduler.schedule {
							expect(NSThread.isMainThread()) == false
							value += 1
						}
					}

					expect(value) == 0

					scheduler.queue.resume()
					expect{value}.toEventually(equal(5))
				}

				it("should run enqueued actions after a given date") {
					var didRun = false
					scheduler.scheduleAfter(NSDate()) {
						didRun = true
						expect(NSThread.isMainThread()) == false
					}

					expect(didRun) == false

					scheduler.queue.resume()
					expect{didRun}.toEventually(beTruthy())
				}

				it("should repeatedly run actions after a given date") {
					let disposable = SerialDisposable()

					var count = 0
					let timesToRun = 3

					disposable.innerDisposable = scheduler.scheduleAfter(NSDate(), repeatingEvery: 0.01, withLeeway: 0) {
						expect(NSThread.isMainThread()) == false

						count += 1

						if count == timesToRun {
							disposable.dispose()
						}
					}

					expect(count) == 0

					scheduler.queue.resume()
					expect{count}.toEventually(equal(timesToRun))
				}
			}
		}

		describe("TestScheduler") {
			var scheduler: TestScheduler!
			var startDate: NSDate!

			// How much dates are allowed to differ when they should be "equal."
			let dateComparisonDelta = 0.00001

			beforeEach {
				startDate = NSDate()

				scheduler = TestScheduler(startDate: startDate)
				expect(scheduler.currentDate) == startDate
			}

			it("should run immediately enqueued actions upon advancement") {
				var string = ""

				scheduler.schedule {
					string += "foo"
					expect(NSThread.isMainThread()) == true
				}

				scheduler.schedule {
					string += "bar"
					expect(NSThread.isMainThread()) == true
				}

				expect(string) == ""

				scheduler.advance()
				expect(scheduler.currentDate).to(beCloseTo(startDate))

				expect(string) == "foobar"
			}

			it("should run actions when advanced past the target date") {
				var string = ""

				scheduler.scheduleAfter(15) { [weak scheduler] in
					string += "bar"
					expect(NSThread.isMainThread()) == true
					expect(scheduler?.currentDate).to(beCloseTo(startDate.dateByAddingTimeInterval(15), within: dateComparisonDelta))
				}

				scheduler.scheduleAfter(5) { [weak scheduler] in
					string += "foo"
					expect(NSThread.isMainThread()) == true
					expect(scheduler?.currentDate).to(beCloseTo(startDate.dateByAddingTimeInterval(5), within: dateComparisonDelta))
				}

				expect(string) == ""

				scheduler.advanceByInterval(10)
				expect(scheduler.currentDate).to(beCloseTo(startDate.dateByAddingTimeInterval(10), within: dateComparisonDelta))
				expect(string) == "foo"

				scheduler.advanceByInterval(10)
				expect(scheduler.currentDate).to(beCloseTo(startDate.dateByAddingTimeInterval(20), within: dateComparisonDelta))
				expect(string) == "foobar"
			}

			it("should run all remaining actions in order") {
				var string = ""

				scheduler.scheduleAfter(15) {
					string += "bar"
					expect(NSThread.isMainThread()) == true
				}

				scheduler.scheduleAfter(5) {
					string += "foo"
					expect(NSThread.isMainThread()) == true
				}

				scheduler.schedule {
					string += "fuzzbuzz"
					expect(NSThread.isMainThread()) == true
				}

				expect(string) == ""

				scheduler.run()
				expect(scheduler.currentDate) == NSDate.distantFuture()
				expect(string) == "fuzzbuzzfoobar"
			}
		}
	}
}
