def f() =
  j = json()
  j.add("foo", 1)
  j.add("bla", "bar")
  j.add("baz", 3.14)
  j.add("key_with_methods", "value".{method=123})
  j.add("record", {a=1, b="ert"})
  j.remove("foo")
  j = yaml.stringify(j)
  test.equal(j, 'record:
  a: 1
  b: ert
key_with_methods: value
bla: bar
baz: 3.14
')

  let yaml.parse (x :
    {
      bla: string,
      baz: float,
      key_with_methods: string,
      record: {a: float, b: string}
    }
  ) = j

  test.equal(
    x, {bla="bar", baz=3.14, key_with_methods="value", record={a=1., b="ert"}}
  )

  test.pass()
end

test.check(f)
