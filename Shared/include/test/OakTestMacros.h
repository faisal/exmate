#ifndef OAK_TEST_MACROS_H_XCTEST
#define OAK_TEST_MACROS_H_XCTEST

// Test assertion macros and utilities extracted from bin/gen_test.
// Used by both the original test runner and XCTest wrappers.

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>
#include <type_traits>
#include <oak/iterator_macros.h>

static std::string oak_format (char const* format, ...) __attribute__ ((format (printf, 1, 2)));
static std::string oak_format (char const* format, ...)
{
  char* tmp = NULL;

  va_list ap;
  va_start(ap, format);
  vasprintf(&tmp, format, ap);
  va_end(ap);

  std::string res(tmp);
  free(tmp);
  return res;
}

static std::string to_s (bool value)               { return value ? "YES" : "NO"; }
static std::string to_s (char value)               { return oak_format("%c", value); }
static std::string to_s (size_t value)             { return oak_format("%zu", value); }
static std::string to_s (ssize_t value)            { return oak_format("%zd", value); }
static std::string to_s (int16_t value)            { return oak_format("%d", value); }
static std::string to_s (uint16_t value)           { return oak_format("%u", value); }
static std::string to_s (int32_t value)            { return oak_format("%d", value); }
static std::string to_s (uint32_t value)           { return oak_format("%u", value); }
static std::string to_s (int64_t value)            { return oak_format("%lld", value); }
static std::string to_s (uint64_t value)           { return oak_format("%llu", value); }
static std::string to_s (double value)             { return oak_format("%g", value); }
static std::string to_s (char const* value)        { return value == NULL     ? "\u00ABNULL\u00BB"     : oak_format("\"%s\"", value); }
static std::string to_s (std::string const& value) { return value == NULL_STR ? "\u00ABNULL_STR\u00BB" : "\"" + value + "\""; }

template <typename _X, typename _Y>
static std::string to_s (std::pair<_X, _Y> const& pair)
{
  return "pair<" + to_s(pair.first) + ", " + to_s(pair.second) + ">";
}

template <typename _T>
static std::string to_s (_T const& container)
{
  std::string res = "( ";
  for(auto element : container)
    res += to_s(element) + ", ";
  res += ")";
  return res;
}

static void oak_warning (std::string const& message, char const* file, int line)
{
  fprintf(stderr, "%s:%d: %s\n", file, line, message.c_str());
}

struct oak_exception : std::exception
{
  oak_exception (std::string const& message) : _message(message) { }
  virtual char const* what () const noexcept { return _message.c_str(); }
private:
  std::string _message;
};

static void oak_assertion_error (std::string const& message, char const* file, int line)
{
  throw oak_exception(oak_format("%s:%d: ", file, line) + message);
}

static std::string oak_format_bad_relation (char const* lhs, char const* op, char const* rhs, std::string const& realLHS, char const* realOp, std::string const& realRHS)
{
  return oak_format("Expected (%s %s %s), found (%s %s %s)", lhs, op, rhs, realLHS.c_str(), realOp, realRHS.c_str());
}

#define OAK_TYPE_OF(x)          std::remove_reference<decltype(x)>::type

#define OAK_WARN(msg)           oak_warning(msg, __FILE__, __LINE__)
#define OAK_FAIL(msg)           oak_assertion_error(msg, __FILE__, __LINE__)

#define OAK_ASSERT(expr)        if(!(expr))                 oak_assertion_error(oak_format("Assertion failed: %s", #expr), __FILE__, __LINE__)
#define OAK_ASSERT_LT(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs <  _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, "<",  #rhs, to_s(_lhs), ">=", to_s(_rhs)), __FILE__, __LINE__); } while(false)
#define OAK_ASSERT_LE(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs <= _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, "<=", #rhs, to_s(_lhs), ">",  to_s(_rhs)), __FILE__, __LINE__); } while(false)
#define OAK_ASSERT_GT(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs >  _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, ">",  #rhs, to_s(_lhs), "<=", to_s(_rhs)), __FILE__, __LINE__); } while(false)
#define OAK_ASSERT_GE(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs >= _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, ">=", #rhs, to_s(_lhs), "<",  to_s(_rhs)), __FILE__, __LINE__); } while(false)
#define OAK_ASSERT_EQ(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs == _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, "==", #rhs, to_s(_lhs), "!=", to_s(_rhs)), __FILE__, __LINE__); } while(false)
#define OAK_ASSERT_NE(lhs, rhs) do { OAK_TYPE_OF(lhs) _lhs = (lhs); OAK_TYPE_OF(rhs) _rhs = (rhs); if(!(_lhs != _rhs)) oak_assertion_error(oak_format_bad_relation(#lhs, "!=", #rhs, to_s(_lhs), "==", to_s(_rhs)), __FILE__, __LINE__); } while(false)

#define OAK_MASSERT(msg, expr)        if(!(expr))           oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_LT(msg, lhs, rhs) if(!((lhs) <  (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_LE(msg, lhs, rhs) if(!((lhs) <= (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_GT(msg, lhs, rhs) if(!((lhs) >  (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_GE(msg, lhs, rhs) if(!((lhs) >= (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_EQ(msg, lhs, rhs) if(!((lhs) == (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)
#define OAK_MASSERT_NE(msg, lhs, rhs) if(!((lhs) != (rhs))) oak_assertion_error(msg, __FILE__, __LINE__)

#endif /* end of include guard: OAK_TEST_MACROS_H_XCTEST */
