chai = require 'chai'
sinon = require 'sinon'
sinonChai = require 'sinon-chai'

_ = require 'lodash'
async = require 'async'

should = chai.should()
chai.use sinonChai

describe 'patterns', () ->
	url = 'amqp://mq'
	SendReceive = require('../src/patterns').SendReceive
	WorkQueue = require('../src/patterns').WorkQueue
	PubSub = require('../src/patterns').PubSub
	Routing = require('../src/patterns').Routing
	Topic = require('../src/patterns').Topic
	Rpc = require('../src/patterns').Rpc

	describe 'SendReceive', () ->
		it 'should receive message sent from sender', (done) ->
			sender = new SendReceive()
			receiver = new SendReceive()

			async.parallel [
				_.partial sender.connect, url
				_.partial receiver.connect, url
			], () ->
				receiver.receive 'hello', (msg) ->
					msg.should.be.equal 'Hello World!'

					done null

				sender.send 'hello', 'Hello World!'

	describe 'WorkQueue', () ->
		it 'should dispatch jobs to workers', (done) ->
			dispatcher = new WorkQueue()
			worker1 = new WorkQueue()
			worker2 = new WorkQueue()

			async.parallel [
				_.partial dispatcher.connect, url
				_.partial worker1.connect, url
				_.partial worker2.connect, url
			], () ->
				collectedJobs = []

				collectDone = sinon.spy _.after 2, () ->
					_.map(collectedJobs, 'job').sort().should.be.deep.equal ['job1', 'job2']
					_.map(collectedJobs, 'worker').sort().should.be.deep.equal ['worker1', 'worker2']
					collectDone.should.be.calledTwice
					_.delay done, 100, null

				collect = (job, workerName) ->
					collectedJobs.push {job: job, worker: workerName}
					collectDone()

				worker1.work 'jobs', (msg, done) ->
					done null
					collect msg, 'worker1'

				worker2.work 'jobs', (msg, done) ->
					done null
					collect msg, 'worker2'

				dispatcher.dispatch 'jobs', 'job1'
				dispatcher.dispatch 'jobs', 'job2'

	describe 'PubSub', () ->
		it 'should publish to all subscribers', (done) ->
			publisher = new PubSub()
			subscriber1 = new PubSub()
			subscriber2 = new PubSub()

			async.parallel [
				_.partial publisher.connect, url
				_.partial subscriber1.connect, url
				_.partial subscriber2.connect, url
			], () ->
				collectedMsg = []

				collectDone = sinon.spy _.after 2, () ->
					collectedMsg.should.be.deep.equal ['Hello All!', 'Hello All!']
					collectDone.should.be.calledTwice
					_.delay done, 100, null

				collect = (msg) ->
					collectedMsg.push msg
					collectDone()

				subscriber1.subscribe 'pubsub', (msg) ->
					msg.should.be.equal 'Hello All!'
					collect msg

				subscriber2.subscribe 'pubsub', (msg) ->
					msg.should.be.equal 'Hello All!'
					collect msg

				_.delay publisher.publish, 100, 'pubsub', 'Hello All!'

	describe 'Routing', () ->
		it 'should route message base on routing key', (done) ->
			sender = new Routing()
			receiver1 = new Routing()
			receiver2 = new Routing()

			async.parallel [
				_.partial sender.connect, url
				_.partial receiver1.connect, url
				_.partial receiver2.connect, url
			], () ->
				collectedMsg = []

				collectDone = sinon.spy _.after 3, () ->
					collectedMsg.sort().should.be.deep.equal ['Hello World!', 'Run. Run. Or it will explode.', 'Run. Run. Or it will explode.']
					collectDone.should.be.calledThrice
					_.delay done, 100, null

				collect = (msg) ->
					collectedMsg.push msg
					collectDone()

				receiver1.receive 'routing', 'error', (msg) ->
					msg.should.be.equal 'Run. Run. Or it will explode.'
					collect msg

				receiver2.receive 'routing', ['info', 'error'], (msg) ->
					msg.should.be.oneOf ['Run. Run. Or it will explode.', 'Hello World!']
					collect msg

				_.delay sender.send, 100, 'routing', 'info', 'Hello World!'
				_.delay sender.send, 100, 'routing', 'error', 'Run. Run. Or it will explode.'

	describe 'Topic', () ->
		it 'should route message to matching patterns', (done) ->
			sender = new Topic()
			receiver1 = new Topic()
			receiver2 = new Topic()

			async.parallel [
				_.partial sender.connect, url
				_.partial receiver1.connect, url
				_.partial receiver2.connect, url
			], () ->
				collectedMsg = []

				collectDone = sinon.spy _.after 8, () ->
					collectDone.callCount.should.be.equal 8
					_.delay done, 100, null

				collect = (msg) ->
					collectedMsg.push msg
					collectDone()

				receiver1.receive 'topicmq', '*.orange.*', (msg) ->
					msg.should.be.oneOf ['Quick orange rabbit', 'Lazy orange elephant', 'Quick orange fox']
					collect msg

				receiver2.receive 'topicmq', ['*.*.rabbit', 'lazy.#'], (msg) ->
					msg.should.be.oneOf ['Quick orange rabbit', 'Lazy orange elephant', 'Lazy brown fox', 'Lazy pink rabbit', 'Lazy orange male rabbit']
					collect msg

				_.delay sender.send, 100, 'topicmq', 'quick.orange.rabbit', 'Quick orange rabbit'
				_.delay sender.send, 100, 'topicmq', 'lazy.orange.elephant', 'Lazy orange elephant'
				_.delay sender.send, 100, 'topicmq', 'quick.orange.fox', 'Quick orange fox'
				_.delay sender.send, 100, 'topicmq', 'lazy.brown.fox', 'Lazy brown fox'
				_.delay sender.send, 100, 'topicmq', 'lazy.pink.rabbit', 'Lazy pink rabbit'
				_.delay sender.send, 100, 'topicmq', 'quick.brown.fox', 'Quick brown fox'
				_.delay sender.send, 100, 'topicmq', 'orange', 'Orange'
				_.delay sender.send, 100, 'topicmq', 'lazy.orange.male.rabbit', 'Lazy orange male rabbit'

	describe 'Rpc', () ->
		it 'should get reply from rpc call', (done) ->
			client = new Rpc()
			server1 = new Rpc()
			server2 = new Rpc()

			async.parallel [
				_.partial client.connect, url
				_.partial server1.connect, url
				_.partial server2.connect, url
			], () ->
				server1.serve 'rpc', (msg, done) ->
					_.delay done, +msg, null, "Done wait for #{msg} ms"

				server1.serve 'rpc', (msg, done) ->
					_.delay done, +msg / 2, null, "Done wait for #{msg} / 2 ms"

				collectedMsg = []

				collectDone = sinon.spy _.after 2, () ->
					collectedMsg.sort().should.be.deep.equal ['Done wait for 100 / 2 ms', 'Done wait for 100 ms']
					collectDone.should.be.calledTwice
					_.delay done, 100, null

				collect = (msg) ->
					collectedMsg.push msg
					collectDone()

				client.request 'rpc', 100, (reply) ->
					collect reply

				client.request 'rpc', 100, (reply) ->
					collect reply
