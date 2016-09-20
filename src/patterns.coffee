amqp = require 'amqplib/callback_api'
_ = require 'lodash'
uuid = require 'node-uuid'

module.exports = self = {}

class Patterns
	connect: (@url, done) =>
		amqp.connect @url, (err, @conn) =>
			return done err if err
			@conn.createChannel (err, @ch) =>
				done err

class SendReceive extends Patterns
	send: (queueName, msg) =>
		@ch.assertQueue queueName, {durable: false}
		@ch.sendToQueue queueName, new Buffer("#{msg}")

	receive: (queueName, cb) =>
		@ch.assertQueue queueName, {durable: false}

		@ch.consume queueName, ( (msg) ->
			cb msg.content.toString()
		), {noAck: true}

class WorkQueue extends Patterns
	dispatch: (queueName, msg) =>
		@ch.assertQueue queueName, {durable: true}
		@ch.sendToQueue queueName, new Buffer("#{msg}"), {persistent: true}

	work: (queueName, cb) =>
		@ch.assertQueue queueName, {durable: true}
		@ch.prefetch 1

		@ch.consume queueName, ( (msg) =>
			cb msg.content.toString(), (err) =>
				return @ch.nack msg if err
				@ch.ack msg
		), {noAck: false}

class PubSub extends Patterns
	publish: (exchangeName, msg) =>
		@ch.assertExchange exchangeName, 'fanout', {durable: false}

		@ch.publish exchangeName, '', new Buffer("#{msg}")

	subscribe: (exchangeName, cb) =>
		@ch.assertExchange exchangeName, 'fanout', {durable: false}

		@ch.assertQueue '', {exclusive: true}, (err, q) =>
			throw err if err

			@ch.bindQueue q.queue, exchangeName, ''

			@ch.consume q.queue, ( (msg) ->
				cb msg.content.toString()
			), {noAck: true}

class Routing extends Patterns
	send: (exchangeName, routingKey, msg) =>
		@ch.assertExchange exchangeName, 'direct', {durable: false}
		@ch.publish exchangeName, routingKey, new Buffer("#{msg}")

	receive: (exchangeName, routingKeys, cb) =>
		routingKeys = [routingKeys] if !_.isArray routingKeys

		@ch.assertExchange exchangeName, 'direct', {durable: false}

		@ch.assertQueue '', {exclusive: true}, (err, q) =>
			throw err if err

			_.forEach routingKeys, (key) =>
				@ch.bindQueue q.queue, exchangeName, key

			@ch.consume q.queue, ( (msg) ->
				cb msg.content.toString()
			), {noAck: true}

class Topic extends Patterns
	send: (exchangeName, routingKey, msg) =>
		@ch.assertExchange exchangeName, 'topic', {durable: false}
		@ch.publish exchangeName, routingKey, new Buffer("#{msg}")

	receive: (exchangeName, routingKeys, cb) =>
		routingKeys = [routingKeys] if !_.isArray routingKeys

		@ch.assertExchange exchangeName, 'topic', {durable: false}
		@ch.assertQueue '', {exclusive: true}, (err, q) =>
			throw err if err

			_.forEach routingKeys, (key) =>
				@ch.bindQueue q.queue, exchangeName, key

			@ch.consume q.queue, ( (msg) ->
				cb msg.content.toString()
			), {noAck: true}

class Rpc extends Patterns
	request: (queueName, msg, cb) =>
		@ch.assertQueue '', {exclusive: true}, (err, q) =>
			throw err if err

			corr = uuid.v4()

			@ch.consume q.queue, ( (msg) ->
				cb msg.content.toString()
			), {noAck: true}

			@ch.sendToQueue queueName, new Buffer("#{msg}"), {correlationId: corr, replyTo: q.queue}

	serve: (queueName, cb) =>
		@ch.assertQueue queueName, {durable: false}

		@ch.prefetch 1

		@ch.consume queueName, (msg) =>
			cb msg.content.toString(), (err, reply) =>
				throw err if err

				@ch.sendToQueue msg.properties.replyTo, new Buffer(reply), {correlationId: msg.properties.correlationId}
				@ch.ack msg

self.Patterns = Patterns
self.SendReceive = SendReceive
self.WorkQueue = WorkQueue
self.PubSub = PubSub
self.Routing = Routing
self.Topic = Topic
self.Rpc = Rpc

self.patterns = new Patterns()
