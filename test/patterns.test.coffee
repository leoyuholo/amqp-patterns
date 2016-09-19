chai = require 'chai'

should = chai.should()

describe 'patterns', () ->
	patterns = require '../src/patterns'

	describe 'connect', () ->
		it 'should be a function', () ->
			patterns.should.have.property('connect').that.is.a.function
