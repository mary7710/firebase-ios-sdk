/*
 * Copyright 2017 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Firestore/Source/Core/FSTQuery.h"

#import <XCTest/XCTest.h>

#import "Firestore/Source/API/FIRFirestore+Internal.h"
#import "Firestore/Source/Model/FSTDocument.h"

#import "Firestore/Example/Tests/Util/FSTHelpers.h"

#include "Firestore/core/src/firebase/firestore/model/database_id.h"
#include "Firestore/core/src/firebase/firestore/model/field_path.h"
#include "Firestore/core/src/firebase/firestore/model/resource_path.h"
#include "Firestore/core/src/firebase/firestore/util/string_apple.h"
#include "Firestore/core/test/firebase/firestore/testutil/testutil.h"
#include "Firestore/core/test/firebase/firestore/testutil/xcgmock.h"
#include "absl/strings/string_view.h"

namespace testutil = firebase::firestore::testutil;
namespace util = firebase::firestore::util;
using firebase::firestore::core::Query;
using firebase::firestore::model::DatabaseId;
using firebase::firestore::model::DocumentComparator;
using firebase::firestore::model::DocumentState;
using firebase::firestore::model::FieldPath;
using firebase::firestore::model::ResourcePath;
using firebase::firestore::util::ComparisonResult;

using testutil::Array;
using testutil::Field;
using testutil::Filter;
using testutil::Map;
using testutil::Value;

NS_ASSUME_NONNULL_BEGIN

/** Convenience methods for building test queries. */
@interface FSTQuery (Tests)
- (FSTQuery *)queryByAddingSortBy:(const absl::string_view)key ascending:(BOOL)ascending;
@end

@implementation FSTQuery (Tests)

- (FSTQuery *)queryByAddingSortBy:(const absl::string_view)key ascending:(BOOL)ascending {
  return [self queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field(key)
                                                                 ascending:ascending]];
}

@end

@interface FSTQueryTests : XCTestCase
@end

@implementation FSTQueryTests

- (void)testConstructor {
  const ResourcePath path{"rooms", "Firestore", "messages", "0001"};
  FSTQuery *query = [FSTQuery queryWithPath:path];
  XCTAssertNotNil(query);

  XCTAssertEqual(query.sortOrders.count, 1);
  XCTAssertEqual(query.sortOrders[0].field.CanonicalString(), FieldPath::kDocumentKeyPath);
  XCTAssertEqual(query.sortOrders[0].ascending, YES);

  XCTAssertEqual(query.explicitSortOrders.count, 0);
}

- (void)testOrderBy {
  FSTQuery *query = FSTTestQuery("rooms/Firestore/messages");
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("length")
                                                                   ascending:NO]];

  XCTAssertEqual(query.sortOrders.count, 2);
  XCTAssertEqual(query.sortOrders[0].field.CanonicalString(), "length");
  XCTAssertEqual(query.sortOrders[0].ascending, NO);
  XCTAssertEqual(query.sortOrders[1].field.CanonicalString(), FieldPath::kDocumentKeyPath);
  XCTAssertEqual(query.sortOrders[1].ascending, NO);

  XCTAssertEqual(query.explicitSortOrders.count, 1);
  XCTAssertEqual(query.explicitSortOrders[0].field.CanonicalString(), "length");
  XCTAssertEqual(query.explicitSortOrders[0].ascending, NO);
}

- (void)testMatchesBasedOnDocumentKey {
  FSTDocument *doc1 =
      FSTTestDoc("rooms/eros/messages/1", 0, @{@"text" : @"msg1"}, DocumentState::kSynced);
  FSTDocument *doc2 =
      FSTTestDoc("rooms/eros/messages/2", 0, @{@"text" : @"msg2"}, DocumentState::kSynced);
  FSTDocument *doc3 =
      FSTTestDoc("rooms/other/messages/1", 0, @{@"text" : @"msg3"}, DocumentState::kSynced);

  // document query
  FSTQuery *query = FSTTestQuery("rooms/eros/messages/1");
  XCTAssertTrue([query matchesDocument:doc1]);
  XCTAssertFalse([query matchesDocument:doc2]);
  XCTAssertFalse([query matchesDocument:doc3]);
}

- (void)testMatchesCorrectlyForShallowAncestorQuery {
  FSTDocument *doc1 =
      FSTTestDoc("rooms/eros/messages/1", 0, @{@"text" : @"msg1"}, DocumentState::kSynced);
  FSTDocument *doc1Meta =
      FSTTestDoc("rooms/eros/messages/1/meta/1", 0, @{@"meta" : @"mv"}, DocumentState::kSynced);
  FSTDocument *doc2 =
      FSTTestDoc("rooms/eros/messages/2", 0, @{@"text" : @"msg2"}, DocumentState::kSynced);
  FSTDocument *doc3 =
      FSTTestDoc("rooms/other/messages/1", 0, @{@"text" : @"msg3"}, DocumentState::kSynced);

  // shallow ancestor query
  FSTQuery *query = FSTTestQuery("rooms/eros/messages");
  XCTAssertTrue([query matchesDocument:doc1]);
  XCTAssertFalse([query matchesDocument:doc1Meta]);
  XCTAssertTrue([query matchesDocument:doc2]);
  XCTAssertFalse([query matchesDocument:doc3]);
}

- (void)testEmptyFieldsAreAllowedForQueries {
  FSTDocument *doc1 =
      FSTTestDoc("rooms/eros/messages/1", 0, @{@"text" : @"msg1"}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("rooms/eros/messages/2", 0, @{}, DocumentState::kSynced);

  FSTQuery *query =
      [FSTTestQuery("rooms/eros/messages") queryByAddingFilter:Filter("text", "==", "msg1")];
  XCTAssertTrue([query matchesDocument:doc1]);
  XCTAssertFalse([query matchesDocument:doc2]);
}

- (void)testMatchesPrimitiveValuesForFilters {
  FSTQuery *query1 = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", ">=", 2)];
  FSTQuery *query2 = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", "<=", 2)];

  FSTDocument *doc1 = FSTTestDoc("collection/1", 0, @{@"sort" : @1}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("collection/2", 0, @{@"sort" : @2}, DocumentState::kSynced);
  FSTDocument *doc3 = FSTTestDoc("collection/3", 0, @{@"sort" : @3}, DocumentState::kSynced);
  FSTDocument *doc4 = FSTTestDoc("collection/4", 0, @{@"sort" : @NO}, DocumentState::kSynced);
  FSTDocument *doc5 = FSTTestDoc("collection/5", 0, @{@"sort" : @"string"}, DocumentState::kSynced);
  FSTDocument *doc6 = FSTTestDoc("collection/6", 0, @{}, DocumentState::kSynced);

  XCTAssertFalse([query1 matchesDocument:doc1]);
  XCTAssertTrue([query1 matchesDocument:doc2]);
  XCTAssertTrue([query1 matchesDocument:doc3]);
  XCTAssertFalse([query1 matchesDocument:doc4]);
  XCTAssertFalse([query1 matchesDocument:doc5]);
  XCTAssertFalse([query1 matchesDocument:doc6]);

  XCTAssertTrue([query2 matchesDocument:doc1]);
  XCTAssertTrue([query2 matchesDocument:doc2]);
  XCTAssertFalse([query2 matchesDocument:doc3]);
  XCTAssertFalse([query2 matchesDocument:doc4]);
  XCTAssertFalse([query2 matchesDocument:doc5]);
  XCTAssertFalse([query2 matchesDocument:doc6]);
}

- (void)testArrayContainsFilter {
  FSTQuery *query =
      [FSTTestQuery("collection") queryByAddingFilter:Filter("array", "array_contains", 42)];

  // not an array.
  FSTDocument *doc = FSTTestDoc("collection/1", 0, @{@"array" : @1}, DocumentState::kSynced);
  XCTAssertFalse([query matchesDocument:doc]);

  // empty array.
  doc = FSTTestDoc("collection/1", 0, @{@"array" : @[]}, DocumentState::kSynced);
  XCTAssertFalse([query matchesDocument:doc]);

  // array without element (and make sure it doesn't match in a nested field or a different field).
  doc = FSTTestDoc(
      "collection/1", 0,
      @{@"array" : @[ @41, @"42", @{@"a" : @42, @"b" : @[ @42 ]} ], @"different" : @[ @42 ]},
      DocumentState::kSynced);
  XCTAssertFalse([query matchesDocument:doc]);

  // array with element.
  doc = FSTTestDoc("collection/1", 0, @{@"array" : @[ @1, @"2", @42, @{@"a" : @1} ]},
                   DocumentState::kSynced);
  XCTAssertTrue([query matchesDocument:doc]);
}

- (void)testArrayContainsFilterWithObjectValue {
  // Search for arrays containing the object { a: [42] }
  FSTQuery *query = [FSTTestQuery("collection")
      queryByAddingFilter:Filter("array", "array_contains", Map("a", Array(42)))];

  // array without element.
  FSTDocument *doc = FSTTestDoc("collection/1", 0, @{
    @"array" : @[
      @{@"a" : @42}, @{@"a" : @[ @42, @43 ]}, @{@"b" : @[ @42 ]}, @{@"a" : @[ @42 ], @"b" : @42}
    ]
  },
                                DocumentState::kSynced);
  XCTAssertFalse([query matchesDocument:doc]);

  // array with element.
  doc = FSTTestDoc("collection/1", 0, @{@"array" : @[ @1, @"2", @42, @{@"a" : @[ @42 ]} ]},
                   DocumentState::kSynced);
  XCTAssertTrue([query matchesDocument:doc]);
}

- (void)testNullFilter {
  FSTQuery *query = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", "==", nullptr)];
  FSTDocument *doc1 =
      FSTTestDoc("collection/1", 0, @{@"sort" : [NSNull null]}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("collection/2", 0, @{@"sort" : @2}, DocumentState::kSynced);
  FSTDocument *doc3 = FSTTestDoc("collection/2", 0, @{@"sort" : @3.1}, DocumentState::kSynced);
  FSTDocument *doc4 = FSTTestDoc("collection/4", 0, @{@"sort" : @NO}, DocumentState::kSynced);
  FSTDocument *doc5 = FSTTestDoc("collection/5", 0, @{@"sort" : @"string"}, DocumentState::kSynced);

  XCTAssertTrue([query matchesDocument:doc1]);
  XCTAssertFalse([query matchesDocument:doc2]);
  XCTAssertFalse([query matchesDocument:doc3]);
  XCTAssertFalse([query matchesDocument:doc4]);
  XCTAssertFalse([query matchesDocument:doc5]);
}

- (void)testNanFilter {
  FSTQuery *query = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", "==", NAN)];
  FSTDocument *doc1 = FSTTestDoc("collection/1", 0, @{@"sort" : @(NAN)}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("collection/2", 0, @{@"sort" : @2}, DocumentState::kSynced);
  FSTDocument *doc3 = FSTTestDoc("collection/2", 0, @{@"sort" : @3.1}, DocumentState::kSynced);
  FSTDocument *doc4 = FSTTestDoc("collection/4", 0, @{@"sort" : @NO}, DocumentState::kSynced);
  FSTDocument *doc5 = FSTTestDoc("collection/5", 0, @{@"sort" : @"string"}, DocumentState::kSynced);

  XCTAssertTrue([query matchesDocument:doc1]);
  XCTAssertFalse([query matchesDocument:doc2]);
  XCTAssertFalse([query matchesDocument:doc3]);
  XCTAssertFalse([query matchesDocument:doc4]);
  XCTAssertFalse([query matchesDocument:doc5]);
}

- (void)testDoesNotMatchComplexObjectsForFilters {
  FSTQuery *query1 = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", "<=", 2)];
  FSTQuery *query2 = [FSTTestQuery("collection") queryByAddingFilter:Filter("sort", ">=", 2)];

  FSTDocument *doc1 = FSTTestDoc("collection/1", 0, @{@"sort" : @2}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("collection/2", 0, @{@"sort" : @[]}, DocumentState::kSynced);
  FSTDocument *doc3 = FSTTestDoc("collection/3", 0, @{@"sort" : @[ @1 ]}, DocumentState::kSynced);
  FSTDocument *doc4 =
      FSTTestDoc("collection/4", 0, @{@"sort" : @{@"foo" : @2}}, DocumentState::kSynced);
  FSTDocument *doc5 =
      FSTTestDoc("collection/5", 0, @{@"sort" : @{@"foo" : @"bar"}}, DocumentState::kSynced);
  FSTDocument *doc6 =
      FSTTestDoc("collection/6", 0, @{@"sort" : @{}}, DocumentState::kSynced);  // no sort field
  FSTDocument *doc7 =
      FSTTestDoc("collection/7", 0, @{@"sort" : @[ @3, @1 ]}, DocumentState::kSynced);

  XCTAssertTrue([query1 matchesDocument:doc1]);
  XCTAssertFalse([query1 matchesDocument:doc2]);
  XCTAssertFalse([query1 matchesDocument:doc3]);
  XCTAssertFalse([query1 matchesDocument:doc4]);
  XCTAssertFalse([query1 matchesDocument:doc5]);
  XCTAssertFalse([query1 matchesDocument:doc6]);
  XCTAssertFalse([query1 matchesDocument:doc7]);

  XCTAssertTrue([query2 matchesDocument:doc1]);
  XCTAssertFalse([query2 matchesDocument:doc2]);
  XCTAssertFalse([query2 matchesDocument:doc3]);
  XCTAssertFalse([query2 matchesDocument:doc4]);
  XCTAssertFalse([query2 matchesDocument:doc5]);
  XCTAssertFalse([query2 matchesDocument:doc6]);
  XCTAssertFalse([query2 matchesDocument:doc7]);
}

- (void)testDoesntRemoveComplexObjectsWithOrderBy {
  FSTQuery *query1 = [FSTTestQuery("collection")
      queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort") ascending:YES]];

  FSTDocument *doc1 = FSTTestDoc("collection/1", 0, @{@"sort" : @2}, DocumentState::kSynced);
  FSTDocument *doc2 = FSTTestDoc("collection/2", 0, @{@"sort" : @[]}, DocumentState::kSynced);
  FSTDocument *doc3 = FSTTestDoc("collection/3", 0, @{@"sort" : @[ @1 ]}, DocumentState::kSynced);
  FSTDocument *doc4 =
      FSTTestDoc("collection/4", 0, @{@"sort" : @{@"foo" : @2}}, DocumentState::kSynced);
  FSTDocument *doc5 =
      FSTTestDoc("collection/5", 0, @{@"sort" : @{@"foo" : @"bar"}}, DocumentState::kSynced);
  FSTDocument *doc6 = FSTTestDoc("collection/6", 0, @{}, DocumentState::kSynced);

  XCTAssertTrue([query1 matchesDocument:doc1]);
  XCTAssertTrue([query1 matchesDocument:doc2]);
  XCTAssertTrue([query1 matchesDocument:doc3]);
  XCTAssertTrue([query1 matchesDocument:doc4]);
  XCTAssertTrue([query1 matchesDocument:doc5]);
  XCTAssertFalse([query1 matchesDocument:doc6]);
}

- (void)testFiltersBasedOnArrayValue {
  FSTQuery *baseQuery = FSTTestQuery("collection");
  FSTDocument *doc1 =
      FSTTestDoc("collection/doc", 0, @{@"tags" : @[ @"foo", @1, @YES ]}, DocumentState::kSynced);

  Query::FilterList matchingFilters = {Filter("tags", "==", Array("foo", 1, true))};

  Query::FilterList nonMatchingFilters = {
      Filter("tags", "==", "foo"),
      Filter("tags", "==", Array("foo", 1)),
      Filter("tags", "==", Array("foo", true, 1)),
  };

  for (const auto &filter : matchingFilters) {
    XCTAssertTrue([[baseQuery queryByAddingFilter:filter] matchesDocument:doc1]);
  }

  for (const auto &filter : nonMatchingFilters) {
    XCTAssertFalse([[baseQuery queryByAddingFilter:filter] matchesDocument:doc1]);
  }
}

- (void)testFiltersBasedOnObjectValue {
  FSTQuery *baseQuery = FSTTestQuery("collection");
  FSTDocument *doc1 = FSTTestDoc(
      "collection/doc", 0, @{@"tags" : @{@"foo" : @"foo", @"a" : @0, @"b" : @YES, @"c" : @(NAN)}},
      DocumentState::kSynced);

  Query::FilterList matchingFilters = {
      Filter("tags", "==", Map("foo", "foo", "a", 0, "b", true, "c", NAN)),
      Filter("tags", "==", Map("b", true, "a", 0, "foo", "foo", "c", NAN)),
      Filter("tags.foo", "==", "foo")};

  Query::FilterList nonMatchingFilters = {
      Filter("tags", "==", "foo"), Filter("tags", "==", Map("foo", "foo", "a", 0, "b", true))};

  for (const auto &filter : matchingFilters) {
    XCTAssertTrue([[baseQuery queryByAddingFilter:filter] matchesDocument:doc1]);
  }

  for (const auto &filter : nonMatchingFilters) {
    XCTAssertFalse([[baseQuery queryByAddingFilter:filter] matchesDocument:doc1]);
  }
}

/**
 * Checks that an ordered array of elements yields the correct pair-wise comparison result for the
 * supplied comparator.
 */
- (void)assertCorrectComparisonsWithArray:(NSArray *)array
                               comparator:(const DocumentComparator &)comp {
  [array enumerateObjectsUsingBlock:^(id iObj, NSUInteger i, BOOL *outerStop) {
    [array enumerateObjectsUsingBlock:^(id _Nonnull jObj, NSUInteger j, BOOL *innerStop) {
      ComparisonResult expected = util::Compare(i, j);
      ComparisonResult actual = comp.Compare(iObj, jObj);
      XCTAssertEqual(actual, expected, @"Compared %@ to %@ at (%lu, %lu).", iObj, jObj,
                     (unsigned long)i, (unsigned long)j);
    }];
  }];
}

- (void)testSortsDocumentsInTheCorrectOrder {
  FSTQuery *query = FSTTestQuery("collection");
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort")
                                                                   ascending:YES]];

  // clang-format off
  NSArray<FSTDocument *> *docs = @[
      FSTTestDoc("collection/1", 0, @{@"sort": [NSNull null]}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @NO}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @YES}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @1}, DocumentState::kSynced),
      FSTTestDoc("collection/2", 0, @{@"sort": @1}, DocumentState::kSynced),  // by key
      FSTTestDoc("collection/3", 0, @{@"sort": @1}, DocumentState::kSynced),  // by key
      FSTTestDoc("collection/1", 0, @{@"sort": @1.9}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @2}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @2.1}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @""}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @"a"}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @"ab"}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort": @"b"}, DocumentState::kSynced),
      FSTTestDoc("collection/1", 0, @{@"sort":
          FSTTestRef("project", DatabaseId::kDefault, @"collection/id1")}, DocumentState::kSynced),
  ];
  // clang-format on

  [self assertCorrectComparisonsWithArray:docs comparator:query.comparator];
}

- (void)testSortsDocumentsUsingMultipleFields {
  FSTQuery *query = FSTTestQuery("collection");
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort1")
                                                                   ascending:YES]];
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort2")
                                                                   ascending:YES]];

  // clang-format off
  NSArray<FSTDocument *> *docs =
      @[FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @1}, DocumentState::kSynced),
        FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),
        FSTTestDoc("collection/2", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/3", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @3}, DocumentState::kSynced),
        FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @1}, DocumentState::kSynced),
        FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),
        FSTTestDoc("collection/2", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/3", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @3}, DocumentState::kSynced),
        ];
  // clang-format on

  [self assertCorrectComparisonsWithArray:docs comparator:query.comparator];
}

- (void)testSortsDocumentsWithDescendingToo {
  FSTQuery *query = FSTTestQuery("collection");
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort1")
                                                                   ascending:NO]];
  query = [query queryByAddingSortOrder:[FSTSortOrder sortOrderWithFieldPath:Field("sort2")
                                                                   ascending:NO]];

  // clang-format off
  NSArray<FSTDocument *> *docs =
      @[FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @3}, DocumentState::kSynced),
        FSTTestDoc("collection/3", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),
        FSTTestDoc("collection/2", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @2, @"sort2": @1}, DocumentState::kSynced),
        FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @3}, DocumentState::kSynced),
        FSTTestDoc("collection/3", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),
        FSTTestDoc("collection/2", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @2}, DocumentState::kSynced),  // by key
        FSTTestDoc("collection/1", 0, @{@"sort1": @1, @"sort2": @1}, DocumentState::kSynced),
        ];
  // clang-format on

  [self assertCorrectComparisonsWithArray:docs comparator:query.comparator];
}

- (void)testEquality {
  FSTQuery *q11 = FSTTestQuery("foo");
  q11 = [q11 queryByAddingFilter:Filter("i1", "<", 2)];
  q11 = [q11 queryByAddingFilter:Filter("i2", "==", 3)];
  FSTQuery *q12 = FSTTestQuery("foo");
  q12 = [q12 queryByAddingFilter:Filter("i2", "==", 3)];
  q12 = [q12 queryByAddingFilter:Filter("i1", "<", 2)];

  FSTQuery *q21 = FSTTestQuery("foo");
  FSTQuery *q22 = FSTTestQuery("foo");

  FSTQuery *q31 = FSTTestQuery("foo/bar");
  FSTQuery *q32 = FSTTestQuery("foo/bar");

  FSTQuery *q41 = FSTTestQuery("foo");
  q41 = [q41 queryByAddingSortBy:"foo" ascending:YES];
  q41 = [q41 queryByAddingSortBy:"bar" ascending:YES];
  FSTQuery *q42 = FSTTestQuery("foo");
  q42 = [q42 queryByAddingSortBy:"foo" ascending:YES];
  q42 = [q42 queryByAddingSortBy:"bar" ascending:YES];
  FSTQuery *q43Diff = FSTTestQuery("foo");
  q43Diff = [q43Diff queryByAddingSortBy:"bar" ascending:YES];
  q43Diff = [q43Diff queryByAddingSortBy:"foo" ascending:YES];

  FSTQuery *q51 = FSTTestQuery("foo");
  q51 = [q51 queryByAddingSortBy:"foo" ascending:YES];
  q51 = [q51 queryByAddingFilter:Filter("foo", ">", 2)];
  FSTQuery *q52 = FSTTestQuery("foo");
  q52 = [q52 queryByAddingFilter:Filter("foo", ">", 2)];
  q52 = [q52 queryByAddingSortBy:"foo" ascending:YES];
  FSTQuery *q53Diff = FSTTestQuery("foo");
  q53Diff = [q53Diff queryByAddingFilter:Filter("bar", ">", 2)];
  q53Diff = [q53Diff queryByAddingSortBy:"bar" ascending:YES];

  FSTQuery *q61 = FSTTestQuery("foo");
  q61 = [q61 queryBySettingLimit:10];

  // XCTAssertEqualObjects(q11, q12);  // TODO(klimt): not canonical yet
  XCTAssertNotEqualObjects(q11, q21);
  XCTAssertNotEqualObjects(q11, q31);
  XCTAssertNotEqualObjects(q11, q41);
  XCTAssertNotEqualObjects(q11, q51);
  XCTAssertNotEqualObjects(q11, q61);

  XCTAssertEqualObjects(q21, q22);
  XCTAssertNotEqualObjects(q21, q31);
  XCTAssertNotEqualObjects(q21, q41);
  XCTAssertNotEqualObjects(q21, q51);
  XCTAssertNotEqualObjects(q21, q61);

  XCTAssertEqualObjects(q31, q32);
  XCTAssertNotEqualObjects(q31, q41);
  XCTAssertNotEqualObjects(q31, q51);
  XCTAssertNotEqualObjects(q31, q61);

  XCTAssertEqualObjects(q41, q42);
  XCTAssertNotEqualObjects(q41, q43Diff);
  XCTAssertNotEqualObjects(q41, q51);
  XCTAssertNotEqualObjects(q41, q61);

  XCTAssertEqualObjects(q51, q52);
  XCTAssertNotEqualObjects(q51, q53Diff);
  XCTAssertNotEqualObjects(q51, q61);
}

- (void)testUniqueIds {
  FSTQuery *q11 = FSTTestQuery("foo");
  q11 = [q11 queryByAddingFilter:Filter("i1", "<", 2)];
  q11 = [q11 queryByAddingFilter:Filter("i2", "==", 3)];
  FSTQuery *q12 = FSTTestQuery("foo");
  q12 = [q12 queryByAddingFilter:Filter("i2", "==", 3)];
  q12 = [q12 queryByAddingFilter:Filter("i1", "<", 2)];

  FSTQuery *q21 = FSTTestQuery("foo");
  FSTQuery *q22 = FSTTestQuery("foo");

  FSTQuery *q31 = FSTTestQuery("foo/bar");
  FSTQuery *q32 = FSTTestQuery("foo/bar");

  FSTQuery *q41 = FSTTestQuery("foo");
  q41 = [q41 queryByAddingSortBy:"foo" ascending:YES];
  q41 = [q41 queryByAddingSortBy:"bar" ascending:YES];
  FSTQuery *q42 = FSTTestQuery("foo");
  q42 = [q42 queryByAddingSortBy:"foo" ascending:YES];
  q42 = [q42 queryByAddingSortBy:"bar" ascending:YES];
  FSTQuery *q43Diff = FSTTestQuery("foo");
  q43Diff = [q43Diff queryByAddingSortBy:"bar" ascending:YES];
  q43Diff = [q43Diff queryByAddingSortBy:"foo" ascending:YES];

  FSTQuery *q51 = FSTTestQuery("foo");
  q51 = [q51 queryByAddingSortBy:"foo" ascending:YES];
  q51 = [q51 queryByAddingFilter:Filter("foo", ">", 2)];
  FSTQuery *q52 = FSTTestQuery("foo");
  q52 = [q52 queryByAddingFilter:Filter("foo", ">", 2)];
  q52 = [q52 queryByAddingSortBy:"foo" ascending:YES];
  FSTQuery *q53Diff = FSTTestQuery("foo");
  q53Diff = [q53Diff queryByAddingFilter:Filter("bar", ">", 2)];
  q53Diff = [q53Diff queryByAddingSortBy:"bar" ascending:YES];

  FSTQuery *q61 = FSTTestQuery("foo");
  q61 = [q61 queryBySettingLimit:10];

  // XCTAssertEqual(q11.hash, q12.hash);  // TODO(klimt): not canonical yet
  XCTAssertNotEqual(q11.hash, q21.hash);
  XCTAssertNotEqual(q11.hash, q31.hash);
  XCTAssertNotEqual(q11.hash, q41.hash);
  XCTAssertNotEqual(q11.hash, q51.hash);
  XCTAssertNotEqual(q11.hash, q61.hash);

  XCTAssertEqual(q21.hash, q22.hash);
  XCTAssertNotEqual(q21.hash, q31.hash);
  XCTAssertNotEqual(q21.hash, q41.hash);
  XCTAssertNotEqual(q21.hash, q51.hash);
  XCTAssertNotEqual(q21.hash, q61.hash);

  XCTAssertEqual(q31.hash, q32.hash);
  XCTAssertNotEqual(q31.hash, q41.hash);
  XCTAssertNotEqual(q31.hash, q51.hash);
  XCTAssertNotEqual(q31.hash, q61.hash);

  XCTAssertEqual(q41.hash, q42.hash);
  XCTAssertNotEqual(q41.hash, q43Diff.hash);
  XCTAssertNotEqual(q41.hash, q51.hash);
  XCTAssertNotEqual(q41.hash, q61.hash);

  XCTAssertEqual(q51.hash, q52.hash);
  XCTAssertNotEqual(q51.hash, q53Diff.hash);
  XCTAssertNotEqual(q51.hash, q61.hash);
}

- (void)testImplicitOrderBy {
  FSTQuery *baseQuery = FSTTestQuery("foo");
  // Default is ascending
  XCTAssertEqualObjects(baseQuery.sortOrders,
                        @[ FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc") ]);

  // Explicit key ordering is respected
  XCTAssertEqualObjects(
      [baseQuery queryByAddingSortOrder:FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc")]
          .sortOrders,
      @[ FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc") ]);
  XCTAssertEqualObjects(
      [baseQuery queryByAddingSortOrder:FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc")]
          .sortOrders,
      @[ FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc") ]);

  XCTAssertEqualObjects(
      [[baseQuery queryByAddingSortOrder:FSTTestOrderBy("foo", @"asc")]
          queryByAddingSortOrder:FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc")]
          .sortOrders,
      (@[ FSTTestOrderBy("foo", @"asc"), FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc") ]));

  XCTAssertEqualObjects(
      [[baseQuery queryByAddingSortOrder:FSTTestOrderBy("foo", @"asc")]
          queryByAddingSortOrder:FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc")]
          .sortOrders,
      (@[ FSTTestOrderBy("foo", @"asc"), FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc") ]));

  // Inequality filters add order bys
  XCTAssertEqualObjects(
      [baseQuery queryByAddingFilter:Filter("foo", "<", 5)].sortOrders,
      (@[ FSTTestOrderBy("foo", @"asc"), FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc") ]));

  // Descending order by applies to implicit key ordering
  XCTAssertEqualObjects(
      [baseQuery queryByAddingSortOrder:FSTTestOrderBy("foo", @"desc")].sortOrders,
      (@[ FSTTestOrderBy("foo", @"desc"), FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc") ]));
  XCTAssertEqualObjects([[baseQuery queryByAddingSortOrder:FSTTestOrderBy("foo", @"asc")]
                            queryByAddingSortOrder:FSTTestOrderBy("bar", @"desc")]
                            .sortOrders,
                        (@[
                          FSTTestOrderBy("foo", @"asc"), FSTTestOrderBy("bar", @"desc"),
                          FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"desc")
                        ]));
  XCTAssertEqualObjects([[baseQuery queryByAddingSortOrder:FSTTestOrderBy("foo", @"desc")]
                            queryByAddingSortOrder:FSTTestOrderBy("bar", @"asc")]
                            .sortOrders,
                        (@[
                          FSTTestOrderBy("foo", @"desc"), FSTTestOrderBy("bar", @"asc"),
                          FSTTestOrderBy(FieldPath::kDocumentKeyPath, @"asc")
                        ]));
}

MATCHER_P(HasCanonicalId, expected, "") {
  std::string actual = util::MakeString([arg canonicalID]);
  *result_listener << "which has canonicalID " << actual;
  return actual == expected;
}

- (void)testCanonicalIDs {
  FSTQuery *query = FSTTestQuery("coll");
  XC_ASSERT_THAT(query, HasCanonicalId("coll|f:|ob:__name__asc"));

  FSTQuery *cg = [FSTQuery queryWithPath:ResourcePath::Empty()
                         collectionGroup:std::make_shared<const std::string>("foo")];
  XC_ASSERT_THAT(cg, HasCanonicalId("|cg:foo|f:|ob:__name__asc"));

  FSTQuery *subcoll = FSTTestQuery("foo/bar/baz");
  XC_ASSERT_THAT(subcoll, HasCanonicalId("foo/bar/baz|f:|ob:__name__asc"));

  FSTQuery *filters = FSTTestQuery("coll");
  filters = [filters queryByAddingFilter:Filter("str", "==", "foo")];
  XC_ASSERT_THAT(filters, HasCanonicalId("coll|f:str==foo|ob:__name__asc"));

  // Inequality filters end up in the order by too
  filters = [filters queryByAddingFilter:Filter("int", "<", 42)];
  XC_ASSERT_THAT(filters, HasCanonicalId("coll|f:str==fooint<42|ob:intasc__name__asc"));

  FSTQuery *orderBys = FSTTestQuery("coll");
  orderBys = [orderBys queryByAddingSortBy:"up" ascending:true];
  XC_ASSERT_THAT(orderBys, HasCanonicalId("coll|f:|ob:upasc__name__asc"));

  // __name__'s order matches the trailing component
  orderBys = [orderBys queryByAddingSortBy:"down" ascending:false];
  XC_ASSERT_THAT(orderBys, HasCanonicalId("coll|f:|ob:upascdowndesc__name__desc"));

  FSTQuery *limit = [FSTTestQuery("coll") queryBySettingLimit:25];
  XC_ASSERT_THAT(limit, HasCanonicalId("coll|f:|ob:__name__asc|l:25"));

  FSTQuery *bounds = FSTTestQuery("airports");
  bounds = [bounds queryByAddingSortBy:"name" ascending:YES];
  bounds = [bounds queryByAddingSortBy:"score" ascending:NO];
  bounds = [bounds queryByAddingStartAt:[FSTBound boundWithPosition:{Value("OAK"), Value(1000)}
                                                           isBefore:true]];
  bounds = [bounds queryByAddingEndAt:[FSTBound boundWithPosition:{Value("SFO"), Value(2000)}
                                                         isBefore:false]];
  XC_ASSERT_THAT(
      bounds,
      HasCanonicalId("airports|f:|ob:nameascscoredesc__name__desc|lb:b:OAK1000|ub:a:SFO2000"));
}

@end

NS_ASSUME_NONNULL_END
