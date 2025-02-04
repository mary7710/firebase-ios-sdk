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

#import <FirebaseCore/FIRAppInternal.h>
#import <FirebaseFirestore/FirebaseFirestore.h>

#import <XCTest/XCTest.h>

#import "Firestore/Example/Tests/Util/FSTEventAccumulator.h"
#import "Firestore/Example/Tests/Util/FSTIntegrationTestCase.h"
#import "Firestore/Source/API/FIRFirestore+Internal.h"

using firebase::firestore::util::TimerId;

@interface FIRDatabaseTests : FSTIntegrationTestCase
@end

@implementation FIRDatabaseTests

- (void)testCanUpdateAnExistingDocument {
  FIRDocumentReference *doc = [self.db documentWithPath:@"rooms/eros"];
  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};
  NSDictionary<NSString *, id> *updateData =
      @{@"desc" : @"NewDescription", @"owner.email" : @"new@xyz.com"};
  NSDictionary<NSString *, id> *finalData =
      @{@"desc" : @"NewDescription", @"owner" : @{@"name" : @"Jonny", @"email" : @"new@xyz.com"}};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *updateCompletion = [self expectationWithDescription:@"updateData"];
  [doc updateData:updateData
       completion:^(NSError *_Nullable error) {
         XCTAssertNil(error);
         [updateCompletion fulfill];
       }];
  [self awaitExpectations];

  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertTrue(result.exists);
  XCTAssertEqualObjects(result.data, finalData);
}

- (void)testCanUpdateAnUnknownDocument {
  [self readerAndWriterOnDocumentRef:^(NSString *path, FIRDocumentReference *readerRef,
                                       FIRDocumentReference *writerRef) {
    [self writeDocumentRef:writerRef data:@{@"a" : @"a"}];
    [self updateDocumentRef:readerRef data:@{@"b" : @"b"}];

    FIRDocumentSnapshot *writerSnap = [self readDocumentForRef:writerRef
                                                        source:FIRFirestoreSourceCache];
    XCTAssertTrue(writerSnap.exists);

    XCTestExpectation *expectation =
        [self expectationWithDescription:@"testCanUpdateAnUnknownDocument"];
    [readerRef getDocumentWithSource:FIRFirestoreSourceCache
                          completion:^(FIRDocumentSnapshot *doc, NSError *_Nullable error) {
                            XCTAssertNotNil(error);
                            [expectation fulfill];
                          }];
    [self awaitExpectations];

    writerSnap = [self readDocumentForRef:writerRef];
    XCTAssertEqualObjects(writerSnap.data, (@{@"a" : @"a", @"b" : @"b"}));
    FIRDocumentSnapshot *readerSnap = [self readDocumentForRef:writerRef];
    XCTAssertEqualObjects(readerSnap.data, (@{@"a" : @"a", @"b" : @"b"}));
  }];
}

- (void)testCanDeleteAFieldWithAnUpdate {
  FIRDocumentReference *doc = [self.db documentWithPath:@"rooms/eros"];
  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};
  NSDictionary<NSString *, id> *updateData =
      @{@"owner.email" : [FIRFieldValue fieldValueForDelete]};
  NSDictionary<NSString *, id> *finalData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny"}};

  [self writeDocumentRef:doc data:initialData];
  [self updateDocumentRef:doc data:updateData];

  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertTrue(result.exists);
  XCTAssertEqualObjects(result.data, finalData);
}

- (void)testDeleteDocument {
  FIRDocumentReference *doc = [self.db documentWithPath:@"rooms/eros"];
  NSDictionary<NSString *, id> *data = @{@"value" : @"foo"};
  [self writeDocumentRef:doc data:data];
  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(result.data, data);
  [self deleteDocumentRef:doc];
  result = [self readDocumentForRef:doc];
  XCTAssertFalse(result.exists);
}

- (void)testCanRetrieveDocumentThatDoesNotExist {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];
  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertNil(result.data);
  XCTAssertNil(result[@"foo"]);
}

- (void)testCannotUpdateNonexistentDocument {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  XCTestExpectation *setCompletion = [self expectationWithDescription:@"setData"];
  [doc updateData:@{@"owner" : @"abc"}
       completion:^(NSError *_Nullable error) {
         XCTAssertNotNil(error);
         XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
         XCTAssertEqual(error.code, FIRFirestoreErrorCodeNotFound);
         [setCompletion fulfill];
       }];
  [self awaitExpectations];
  FIRDocumentSnapshot *result = [self readDocumentForRef:doc];
  XCTAssertFalse(result.exists);
}

- (void)testCanOverwriteDataAnExistingDocumentUsingSet {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};
  NSDictionary<NSString *, id> *udpateData = @{@"desc" : @"NewDescription"};

  [self writeDocumentRef:doc data:initialData];
  [self writeDocumentRef:doc data:udpateData];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, udpateData);
}

- (void)testCanMergeDataWithAnExistingDocumentUsingSet {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner.data" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};
  NSDictionary<NSString *, id> *mergeData =
      @{@"updated" : @YES, @"owner.data" : @{@"name" : @"Sebastian"}};
  NSDictionary<NSString *, id> *finalData = @{
    @"desc" : @"Description",
    @"updated" : @YES,
    @"owner.data" : @{@"name" : @"Sebastian", @"email" : @"abc@xyz.com"}
  };

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
           merge:YES
      completion:^(NSError *error) {
        XCTAssertNil(error);
        [completed fulfill];
      }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testCanMergeEmptyObject {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  FSTEventAccumulator *accumulator = [FSTEventAccumulator accumulatorForTest:self];
  id<FIRListenerRegistration> listenerRegistration =
      [doc addSnapshotListener:[accumulator valueEventHandler]];

  [self writeDocumentRef:doc data:@{}];
  FIRDocumentSnapshot *snapshot = [accumulator awaitEventWithName:@"Snapshot"];
  XCTAssertEqualObjects(snapshot.data, @{});

  [self mergeDocumentRef:doc data:@{@"a" : @{}} fields:@[ @"a" ]];
  snapshot = [accumulator awaitEventWithName:@"Snapshot"];
  XCTAssertEqualObjects(snapshot.data, @{@"a" : @{}});

  [self mergeDocumentRef:doc data:@{@"b" : @{}}];
  snapshot = [accumulator awaitEventWithName:@"Snapshot"];
  XCTAssertEqualObjects(snapshot.data, (@{@"a" : @{}, @"b" : @{}}));

  snapshot = [self readDocumentForRef:doc source:FIRFirestoreSourceServer];
  XCTAssertEqualObjects(snapshot.data, (@{@"a" : @{}, @"b" : @{}}));

  [listenerRegistration remove];
}

- (void)testCanMergeServerTimestamps {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{
    @"updated" : @NO,
  };
  NSDictionary<NSString *, id> *mergeData = @{
    @"time" : [FIRFieldValue fieldValueForServerTimestamp],
    @"nested" : @{@"time" : [FIRFieldValue fieldValueForServerTimestamp]}
  };

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
           merge:YES
      completion:^(NSError *error) {
        XCTAssertNil(error);
        [completed fulfill];
      }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqual(document[@"updated"], @NO);
  XCTAssertTrue([document[@"time"] isKindOfClass:[FIRTimestamp class]]);
  XCTAssertTrue([document[@"nested.time"] isKindOfClass:[FIRTimestamp class]]);
}

- (void)testCanDeleteFieldUsingMerge {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"untouched" : @YES, @"foo" : @"bar", @"nested" : @{@"untouched" : @YES, @"foo" : @"bar"}};
  NSDictionary<NSString *, id> *mergeData = @{
    @"foo" : [FIRFieldValue fieldValueForDelete],
    @"nested" : @{@"foo" : [FIRFieldValue fieldValueForDelete]}
  };

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
           merge:YES
      completion:^(NSError *error) {
        XCTAssertNil(error);
        [completed fulfill];
      }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqual(document[@"untouched"], @YES);
  XCTAssertNil(document[@"foo"]);
  XCTAssertEqual(document[@"nested.untouched"], @YES);
  XCTAssertNil(document[@"nested.foo"]);
}

- (void)testCanDeleteFieldUsingMergeFields {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{
    @"untouched" : @YES,
    @"foo" : @"bar",
    @"inner" : @{@"removed" : @YES, @"foo" : @"bar"},
    @"nested" : @{@"untouched" : @YES, @"foo" : @"bar"}
  };
  NSDictionary<NSString *, id> *mergeData = @{
    @"foo" : [FIRFieldValue fieldValueForDelete],
    @"inner" : @{@"foo" : [FIRFieldValue fieldValueForDelete]},
    @"nested" : @{
      @"untouched" : [FIRFieldValue fieldValueForDelete],
      @"foo" : [FIRFieldValue fieldValueForDelete]
    }
  };
  NSDictionary<NSString *, id> *finalData =
      @{@"untouched" : @YES, @"inner" : @{}, @"nested" : @{@"untouched" : @YES}};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
      mergeFields:@[ @"foo", @"inner", @"nested.foo" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects([document data], finalData);
}

- (void)testCanSetServerTimestampsUsingMergeFields {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"untouched" : @YES, @"foo" : @"bar", @"nested" : @{@"untouched" : @YES, @"foo" : @"bar"}};
  NSDictionary<NSString *, id> *mergeData = @{
    @"foo" : [FIRFieldValue fieldValueForServerTimestamp],
    @"inner" : @{@"foo" : [FIRFieldValue fieldValueForServerTimestamp]},
    @"nested" : @{@"foo" : [FIRFieldValue fieldValueForServerTimestamp]}
  };

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
      mergeFields:@[ @"foo", @"inner", @"nested.foo" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertTrue([document exists]);
  XCTAssertTrue([document[@"foo"] isKindOfClass:[FIRTimestamp class]]);
  XCTAssertTrue([document[@"inner.foo"] isKindOfClass:[FIRTimestamp class]]);
  XCTAssertTrue([document[@"nested.foo"] isKindOfClass:[FIRTimestamp class]]);
}

- (void)testMergeReplacesArrays {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{
    @"untouched" : @YES,
    @"data" : @"old",
    @"topLevel" : @[ @"old", @"old" ],
    @"mapInArray" : @[ @{@"data" : @"old"} ]
  };
  NSDictionary<NSString *, id> *mergeData =
      @{@"data" : @"new", @"topLevel" : @[ @"new" ], @"mapInArray" : @[ @{@"data" : @"new"} ]};
  NSDictionary<NSString *, id> *finalData = @{
    @"untouched" : @YES,
    @"data" : @"new",
    @"topLevel" : @[ @"new" ],
    @"mapInArray" : @[ @{@"data" : @"new"} ]
  };

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanMergeDataWithAnExistingDocumentUsingSet"];

  [doc setData:mergeData
           merge:YES
      completion:^(NSError *error) {
        XCTAssertNil(error);
        [completed fulfill];
      }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testCannotSpecifyFieldMaskForMissingField {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  XCTAssertThrowsSpecific(
      { [doc setData:@{} mergeFields:@[ @"foo" ]]; }, NSException,
      @"Field 'foo' is specified in your field mask but missing from your input data.");
}

- (void)testCanSetASubsetOfFieldsUsingMask {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};

  NSDictionary<NSString *, id> *finalData = @{@"desc" : @"Description", @"owner" : @"Sebastian"};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanSetASubsetOfFieldsUsingMask"];

  [doc setData:@{@"desc" : @"NewDescription", @"owner" : @"Sebastian"}
      mergeFields:@[ @"owner" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testDoesNotApplyFieldDeleteOutsideOfMask {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};

  NSDictionary<NSString *, id> *finalData = @{@"desc" : @"Description", @"owner" : @"Sebastian"};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanSetASubsetOfFieldsUsingMask"];

  [doc setData:@{@"desc" : [FIRFieldValue fieldValueForDelete], @"owner" : @"Sebastian"}
      mergeFields:@[ @"owner" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testDoesNotApplyFieldTransformOutsideOfMask {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};

  NSDictionary<NSString *, id> *finalData = @{@"desc" : @"Description", @"owner" : @"Sebastian"};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanSetASubsetOfFieldsUsingMask"];

  [doc setData:@{@"desc" : [FIRFieldValue fieldValueForServerTimestamp], @"owner" : @"Sebastian"}
      mergeFields:@[ @"owner" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testCanSetEmptyFieldMask {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};

  NSDictionary<NSString *, id> *finalData = initialData;

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanSetASubsetOfFieldsUsingMask"];

  [doc setData:@{@"desc" : [FIRFieldValue fieldValueForServerTimestamp], @"owner" : @"Sebastian"}
      mergeFields:@[]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testCanSpecifyFieldsMultipleTimesInFieldMask {
  FIRDocumentReference *doc = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Jonny", @"email" : @"abc@xyz.com"}};

  NSDictionary<NSString *, id> *finalData =
      @{@"desc" : @"Description", @"owner" : @{@"name" : @"Sebastian", @"email" : @"new@xyz.com"}};

  [self writeDocumentRef:doc data:initialData];

  XCTestExpectation *completed =
      [self expectationWithDescription:@"testCanSetASubsetOfFieldsUsingMask"];

  [doc setData:@{
    @"desc" : @"NewDescription",
    @"owner" : @{@"name" : @"Sebastian", @"email" : @"new@xyz.com"}
  }
      mergeFields:@[ @"owner.name", @"owner", @"owner" ]
       completion:^(NSError *error) {
         XCTAssertNil(error);
         [completed fulfill];
       }];

  [self awaitExpectations];

  FIRDocumentSnapshot *document = [self readDocumentForRef:doc];
  XCTAssertEqualObjects(document.data, finalData);
}

- (void)testAddingToACollectionYieldsTheCorrectDocumentReference {
  FIRCollectionReference *coll = [self.db collectionWithPath:@"collection"];
  FIRDocumentReference *ref = [coll addDocumentWithData:@{@"foo" : @1}];

  XCTestExpectation *getCompletion = [self expectationWithDescription:@"getData"];
  [ref getDocumentWithCompletion:^(FIRDocumentSnapshot *_Nullable document,
                                   NSError *_Nullable error) {
    XCTAssertNil(error);
    XCTAssertEqualObjects(document.data, (@{@"foo" : @1}));

    [getCompletion fulfill];
  }];
  [self awaitExpectations];
}

- (void)testListenCanBeCalledMultipleTimes {
  FIRCollectionReference *coll = [self.db collectionWithPath:@"collection"];
  FIRDocumentReference *doc = [coll documentWithAutoID];

  XCTestExpectation *completed = [self expectationWithDescription:@"multiple addSnapshotListeners"];

  __block NSDictionary<NSString *, id> *resultingData;

  // Shut the compiler up about strong references to doc.
  FIRDocumentReference *__weak weakDoc = doc;

  [doc setData:@{@"foo" : @"bar"}
      completion:^(NSError *error1) {
        XCTAssertNil(error1);
        FIRDocumentReference *strongDoc = weakDoc;

        [strongDoc addSnapshotListener:^(FIRDocumentSnapshot *snapshot2, NSError *error2) {
          XCTAssertNil(error2);

          FIRDocumentReference *strongDoc2 = weakDoc;
          [strongDoc2 addSnapshotListener:^(FIRDocumentSnapshot *snapshot3, NSError *error3) {
            XCTAssertNil(error3);
            resultingData = snapshot3.data;
            [completed fulfill];
          }];
        }];
      }];

  [self awaitExpectations];
  XCTAssertEqualObjects(resultingData, @{@"foo" : @"bar"});
}

- (void)testDocumentSnapshotEvents_nonExistent {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  XCTestExpectation *snapshotCompletion = [self expectationWithDescription:@"snapshot"];
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [docRef addSnapshotListener:^(FIRDocumentSnapshot *_Nullable doc, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertNotNil(doc);
          XCTAssertFalse(doc.exists);
          [snapshotCompletion fulfill];

        } else {
          XCTFail("Should not have received this callback");
        }
      }];

  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forAdd {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  XCTestExpectation *emptyCompletion = [self expectationWithDescription:@"empty snapshot"];
  __block XCTestExpectation *dataCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [docRef addSnapshotListener:^(FIRDocumentSnapshot *_Nullable doc, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertNotNil(doc);
          XCTAssertFalse(doc.exists);
          [emptyCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertEqualObjects(doc.data, (@{@"a" : @1}));
          XCTAssertEqual(doc.metadata.hasPendingWrites, YES);
          [dataCompletion fulfill];

        } else {
          XCTFail("Should not have received this callback");
        }
      }];

  [self awaitExpectations];
  dataCompletion = [self expectationWithDescription:@"data snapshot"];

  [docRef setData:@{@"a" : @1}];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forAddIncludingMetadata {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  XCTestExpectation *emptyCompletion = [self expectationWithDescription:@"empty snapshot"];
  __block XCTestExpectation *dataCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration = [docRef
      addSnapshotListenerWithIncludeMetadataChanges:YES
                                           listener:^(FIRDocumentSnapshot *_Nullable doc,
                                                      NSError *error) {
                                             callbacks++;

                                             if (callbacks == 1) {
                                               XCTAssertNotNil(doc);
                                               XCTAssertFalse(doc.exists);
                                               [emptyCompletion fulfill];

                                             } else if (callbacks == 2) {
                                               XCTAssertEqualObjects(doc.data, (@{@"a" : @1}));
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, YES);

                                             } else if (callbacks == 3) {
                                               XCTAssertEqualObjects(doc.data, (@{@"a" : @1}));
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               [dataCompletion fulfill];

                                             } else {
                                               XCTFail("Should not have received this callback");
                                             }
                                           }];

  [self awaitExpectations];
  dataCompletion = [self expectationWithDescription:@"data snapshot"];

  [docRef setData:@{@"a" : @1}];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forChange {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};
  NSDictionary<NSString *, id> *changedData = @{@"b" : @2};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [docRef addSnapshotListener:^(FIRDocumentSnapshot *_Nullable doc, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertEqualObjects(doc.data, initialData);
          XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
          [initialCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertEqualObjects(doc.data, changedData);
          XCTAssertEqual(doc.metadata.hasPendingWrites, YES);
          [changeCompletion fulfill];

        } else {
          XCTFail("Should not have received this callback");
        }
      }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef setData:changedData];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forChangeIncludingMetadata {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};
  NSDictionary<NSString *, id> *changedData = @{@"b" : @2};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration = [docRef
      addSnapshotListenerWithIncludeMetadataChanges:YES
                                           listener:^(FIRDocumentSnapshot *_Nullable doc,
                                                      NSError *error) {
                                             callbacks++;

                                             if (callbacks == 1) {
                                               XCTAssertEqualObjects(doc.data, initialData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, YES);

                                             } else if (callbacks == 2) {
                                               XCTAssertEqualObjects(doc.data, initialData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, NO);
                                               [initialCompletion fulfill];

                                             } else if (callbacks == 3) {
                                               XCTAssertEqualObjects(doc.data, changedData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, YES);
                                               XCTAssertEqual(doc.metadata.isFromCache, NO);

                                             } else if (callbacks == 4) {
                                               XCTAssertEqualObjects(doc.data, changedData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, NO);
                                               [changeCompletion fulfill];

                                             } else {
                                               XCTFail("Should not have received this callback");
                                             }
                                           }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef setData:changedData];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forDelete {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [docRef addSnapshotListener:^(FIRDocumentSnapshot *_Nullable doc, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertEqualObjects(doc.data, initialData);
          XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
          XCTAssertEqual(doc.metadata.isFromCache, YES);
          [initialCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertFalse(doc.exists);
          [changeCompletion fulfill];

        } else {
          XCTFail("Should not have received this callback");
        }
      }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef deleteDocument];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testDocumentSnapshotEvents_forDeleteIncludingMetadata {
  FIRDocumentReference *docRef = [[self.db collectionWithPath:@"rooms"] documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration = [docRef
      addSnapshotListenerWithIncludeMetadataChanges:YES
                                           listener:^(FIRDocumentSnapshot *_Nullable doc,
                                                      NSError *error) {
                                             callbacks++;

                                             if (callbacks == 1) {
                                               XCTAssertEqualObjects(doc.data, initialData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, YES);

                                             } else if (callbacks == 2) {
                                               XCTAssertEqualObjects(doc.data, initialData);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, NO);
                                               [initialCompletion fulfill];

                                             } else if (callbacks == 3) {
                                               XCTAssertFalse(doc.exists);
                                               XCTAssertEqual(doc.metadata.hasPendingWrites, NO);
                                               XCTAssertEqual(doc.metadata.isFromCache, NO);
                                               [changeCompletion fulfill];

                                             } else {
                                               XCTFail("Should not have received this callback");
                                             }
                                           }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef deleteDocument];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testQuerySnapshotEvents_forAdd {
  FIRCollectionReference *roomsRef = [self collectionRef];
  FIRDocumentReference *docRef = [roomsRef documentWithAutoID];

  NSDictionary<NSString *, id> *newData = @{@"a" : @1};

  XCTestExpectation *emptyCompletion = [self expectationWithDescription:@"empty snapshot"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [roomsRef addSnapshotListener:^(FIRQuerySnapshot *_Nullable docSet, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertEqual(docSet.count, 0);
          [emptyCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertEqual(docSet.count, 1);
          XCTAssertTrue([docSet.documents[0] isKindOfClass:[FIRQueryDocumentSnapshot class]]);
          XCTAssertEqualObjects(docSet.documents[0].data, newData);
          XCTAssertEqual(docSet.documents[0].metadata.hasPendingWrites, YES);
          [changeCompletion fulfill];

        } else {
          XCTFail("Should not have received a third callback");
        }
      }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"changed snapshot"];

  [docRef setData:newData];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testQuerySnapshotEvents_forChange {
  FIRCollectionReference *roomsRef = [self collectionRef];
  FIRDocumentReference *docRef = [roomsRef documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};
  NSDictionary<NSString *, id> *changedData = @{@"b" : @2};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [roomsRef addSnapshotListener:^(FIRQuerySnapshot *_Nullable docSet, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertEqual(docSet.count, 1);
          XCTAssertEqualObjects(docSet.documents[0].data, initialData);
          XCTAssertEqual(docSet.documents[0].metadata.hasPendingWrites, NO);
          [initialCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertEqual(docSet.count, 1);
          XCTAssertEqualObjects(docSet.documents[0].data, changedData);
          XCTAssertEqual(docSet.documents[0].metadata.hasPendingWrites, YES);
          [changeCompletion fulfill];

        } else {
          XCTFail("Should not have received a third callback");
        }
      }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef setData:changedData];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testQuerySnapshotEvents_forDelete {
  FIRCollectionReference *roomsRef = [self collectionRef];
  FIRDocumentReference *docRef = [roomsRef documentWithAutoID];

  NSDictionary<NSString *, id> *initialData = @{@"a" : @1};

  [self writeDocumentRef:docRef data:initialData];

  XCTestExpectation *initialCompletion = [self expectationWithDescription:@"initial data"];
  __block XCTestExpectation *changeCompletion;
  __block int callbacks = 0;

  id<FIRListenerRegistration> listenerRegistration =
      [roomsRef addSnapshotListener:^(FIRQuerySnapshot *_Nullable docSet, NSError *error) {
        callbacks++;

        if (callbacks == 1) {
          XCTAssertEqual(docSet.count, 1);
          XCTAssertEqualObjects(docSet.documents[0].data, initialData);
          XCTAssertEqual(docSet.documents[0].metadata.hasPendingWrites, NO);
          [initialCompletion fulfill];

        } else if (callbacks == 2) {
          XCTAssertEqual(docSet.count, 0);
          [changeCompletion fulfill];

        } else {
          XCTFail("Should not have received a third callback");
        }
      }];

  [self awaitExpectations];
  changeCompletion = [self expectationWithDescription:@"listen for changed data"];

  [docRef deleteDocument];
  [self awaitExpectations];

  [listenerRegistration remove];
}

- (void)testExposesFirestoreOnDocumentReferences {
  FIRDocumentReference *doc = [self.db documentWithPath:@"foo/bar"];
  XCTAssertEqual(doc.firestore, self.db);
}

- (void)testExposesFirestoreOnQueries {
  FIRQuery *q = [[self.db collectionWithPath:@"foo"] queryLimitedTo:5];
  XCTAssertEqual(q.firestore, self.db);
}

- (void)testDocumentReferenceEquality {
  FIRFirestore *firestore = self.db;
  FIRDocumentReference *docRef = [firestore documentWithPath:@"foo/bar"];
  XCTAssertEqualObjects([firestore documentWithPath:@"foo/bar"], docRef);
  XCTAssertEqualObjects([docRef collectionWithPath:@"blah"].parent, docRef);

  XCTAssertNotEqualObjects([firestore documentWithPath:@"foo/BAR"], docRef);

  FIRFirestore *otherFirestore = [self firestore];
  XCTAssertNotEqualObjects([otherFirestore documentWithPath:@"foo/bar"], docRef);
}

- (void)testQueryReferenceEquality {
  FIRFirestore *firestore = self.db;
  FIRQuery *query =
      [[[firestore collectionWithPath:@"foo"] queryOrderedByField:@"bar"] queryWhereField:@"baz"
                                                                                isEqualTo:@42];
  FIRQuery *query2 =
      [[[firestore collectionWithPath:@"foo"] queryOrderedByField:@"bar"] queryWhereField:@"baz"
                                                                                isEqualTo:@42];
  XCTAssertEqualObjects(query, query2);

  FIRQuery *query3 =
      [[[firestore collectionWithPath:@"foo"] queryOrderedByField:@"BAR"] queryWhereField:@"baz"
                                                                                isEqualTo:@42];
  XCTAssertNotEqualObjects(query, query3);

  FIRFirestore *otherFirestore = [self firestore];
  FIRQuery *query4 = [[[otherFirestore collectionWithPath:@"foo"] queryOrderedByField:@"bar"]
      queryWhereField:@"baz"
            isEqualTo:@42];
  XCTAssertNotEqualObjects(query, query4);
}

- (void)testCanTraverseCollectionsAndDocuments {
  NSString *expected = @"a/b/c/d";
  // doc path from root Firestore.
  XCTAssertEqualObjects([self.db documentWithPath:@"a/b/c/d"].path, expected);
  // collection path from root Firestore.
  XCTAssertEqualObjects([[self.db collectionWithPath:@"a/b/c"] documentWithPath:@"d"].path,
                        expected);
  // doc path from CollectionReference.
  XCTAssertEqualObjects([[self.db collectionWithPath:@"a"] documentWithPath:@"b/c/d"].path,
                        expected);
  // collection path from DocumentReference.
  XCTAssertEqualObjects([[self.db documentWithPath:@"a/b"] collectionWithPath:@"c/d/e"].path,
                        @"a/b/c/d/e");
}

- (void)testCanTraverseCollectionAndDocumentParents {
  FIRCollectionReference *collection = [self.db collectionWithPath:@"a/b/c"];
  XCTAssertEqualObjects(collection.path, @"a/b/c");

  FIRDocumentReference *doc = collection.parent;
  XCTAssertEqualObjects(doc.path, @"a/b");

  collection = doc.parent;
  XCTAssertEqualObjects(collection.path, @"a");

  FIRDocumentReference *nilDoc = collection.parent;
  XCTAssertNil(nilDoc);
}

- (void)testUpdateFieldsWithDots {
  FIRDocumentReference *doc = [self documentRef];

  [self writeDocumentRef:doc data:@{@"a.b" : @"old", @"c.d" : @"old"}];

  [self updateDocumentRef:doc
                     data:@{(id)[[FIRFieldPath alloc] initWithFields:@[ @"a.b" ]] : @"new"}];

  XCTestExpectation *expectation = [self expectationWithDescription:@"testUpdateFieldsWithDots"];

  [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
    XCTAssertNil(error);
    XCTAssertEqualObjects(snapshot.data, (@{@"a.b" : @"new", @"c.d" : @"old"}));
    [expectation fulfill];
  }];

  [self awaitExpectations];
}

- (void)testUpdateNestedFields {
  FIRDocumentReference *doc = [self documentRef];

  [self writeDocumentRef:doc
                    data:@{
                      @"a" : @{@"b" : @"old"},
                      @"c" : @{@"d" : @"old"},
                      @"e" : @{@"f" : @"old"}
                    }];

  [self updateDocumentRef:doc
                     data:@{
                       (id) @"a.b" : @"new",
                       (id)[[FIRFieldPath alloc] initWithFields:@[ @"c", @"d" ]] : @"new"
                     }];

  XCTestExpectation *expectation = [self expectationWithDescription:@"testUpdateNestedFields"];

  [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
    XCTAssertNil(error);
    XCTAssertEqualObjects(snapshot.data, (@{
                            @"a" : @{@"b" : @"new"},
                            @"c" : @{@"d" : @"new"},
                            @"e" : @{@"f" : @"old"}
                          }));
    [expectation fulfill];
  }];

  [self awaitExpectations];
}

- (void)testCollectionID {
  XCTAssertEqualObjects([self.db collectionWithPath:@"foo"].collectionID, @"foo");
  XCTAssertEqualObjects([self.db collectionWithPath:@"foo/bar/baz"].collectionID, @"baz");
}

- (void)testDocumentID {
  XCTAssertEqualObjects([self.db documentWithPath:@"foo/bar"].documentID, @"bar");
  XCTAssertEqualObjects([self.db documentWithPath:@"foo/bar/baz/qux"].documentID, @"qux");
}

- (void)testCanQueueWritesWhileOffline {
  XCTestExpectation *writeEpectation = [self expectationWithDescription:@"successfull write"];
  XCTestExpectation *networkExpectation = [self expectationWithDescription:@"enable network"];

  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;
  NSDictionary<NSString *, id> *data = @{@"a" : @"b"};

  [firestore disableNetworkWithCompletion:^(NSError *error) {
    XCTAssertNil(error);

    [doc setData:data
        completion:^(NSError *error) {
          XCTAssertNil(error);
          [writeEpectation fulfill];
        }];

    [firestore enableNetworkWithCompletion:^(NSError *error) {
      XCTAssertNil(error);
      [networkExpectation fulfill];
    }];
  }];

  [self awaitExpectations];

  XCTestExpectation *getExpectation = [self expectationWithDescription:@"successfull get"];
  [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
    XCTAssertNil(error);
    XCTAssertEqualObjects(snapshot.data, data);
    XCTAssertFalse(snapshot.metadata.isFromCache);

    [getExpectation fulfill];
  }];

  [self awaitExpectations];
}

- (void)testCanGetDocumentsWhileOffline {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;
  NSDictionary<NSString *, id> *data = @{@"a" : @"b"};

  XCTestExpectation *failExpectation =
      [self expectationWithDescription:@"offline read with no cached data"];
  XCTestExpectation *onlineExpectation = [self expectationWithDescription:@"online read"];
  XCTestExpectation *networkExpectation = [self expectationWithDescription:@"network online"];

  __weak FIRDocumentReference *weakDoc = doc;

  [firestore disableNetworkWithCompletion:^(NSError *error) {
    XCTAssertNil(error);

    [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
      XCTAssertNotNil(error);
      [failExpectation fulfill];
    }];

    [doc setData:data
        completion:^(NSError *_Nullable error) {
          XCTAssertNil(error);

          [weakDoc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
            XCTAssertNil(error);

            // Verify that we are not reading from cache.
            XCTAssertFalse(snapshot.metadata.isFromCache);
            [onlineExpectation fulfill];
          }];
        }];

    [doc getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
      XCTAssertNil(error);

      // Verify that we are reading from cache.
      XCTAssertTrue(snapshot.metadata.fromCache);
      XCTAssertEqualObjects(snapshot.data, data);
      [firestore enableNetworkWithCompletion:^(NSError *error) {
        [networkExpectation fulfill];
      }];
    }];
  }];

  [self awaitExpectations];
}

- (void)testWriteStreamReconnectsAfterIdle {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;

  [self writeDocumentRef:doc data:@{@"foo" : @"bar"}];
  [firestore workerQueue] -> RunScheduledOperationsUntil(TimerId::WriteStreamIdle);
  [self writeDocumentRef:doc data:@{@"foo" : @"bar"}];
}

- (void)testWatchStreamReconnectsAfterIdle {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;

  [self readSnapshotForRef:[self documentRef] requireOnline:YES];
  [firestore workerQueue] -> RunScheduledOperationsUntil(TimerId::ListenStreamIdle);
  [self readSnapshotForRef:[self documentRef] requireOnline:YES];
}

- (void)testCanDisableNetwork {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;

  [firestore enableNetworkWithCompletion:[self completionForExpectationWithName:@"Enable network"]];
  [self awaitExpectations];
  [firestore
      enableNetworkWithCompletion:[self completionForExpectationWithName:@"Enable network again"]];
  [self awaitExpectations];
  [firestore
      disableNetworkWithCompletion:[self completionForExpectationWithName:@"Disable network"]];
  [self awaitExpectations];
  [firestore
      disableNetworkWithCompletion:[self
                                       completionForExpectationWithName:@"Disable network again"]];
  [self awaitExpectations];
  [firestore
      enableNetworkWithCompletion:[self completionForExpectationWithName:@"Final enable network"]];
  [self awaitExpectations];
}

- (void)testClientCallsAfterShutdownFail {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;

  [firestore enableNetworkWithCompletion:[self completionForExpectationWithName:@"Enable network"]];
  [self awaitExpectations];
  [firestore shutdownWithCompletion:[self completionForExpectationWithName:@"Shutdown"]];
  [self awaitExpectations];

  XCTAssertThrowsSpecific(
      {
        [firestore disableNetworkWithCompletion:^(NSError *error){
        }];
      },
      NSException, @"The client has already been shutdown.");
}

- (void)testMaintainsPersistenceAfterRestarting {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;
  FIRApp *app = firestore.app;
  NSString *appName = app.name;
  FIROptions *options = app.options;

  NSDictionary<NSString *, id> *initialData = @{@"foo" : @"42"};
  [self writeDocumentRef:doc data:initialData];

  // -clearPersistence() requires Firestore to be shut down. Shutdown FIRApp and remove the
  // firestore instance to emulate the way an end user would do this.
  [self shutdownFirestore:firestore];
  [self.firestores removeObject:firestore];
  [self deleteApp:app];

  // We restart the app with the same name and options to check that the previous instance's
  // persistent storage persists its data after restarting. Calling [self firestore] here would
  // create a new instance of firestore, which defeats the purpose of this test.
  [FIRApp configureWithName:appName options:options];
  FIRApp *app2 = [FIRApp appNamed:appName];
  FIRFirestore *firestore2 = [self firestoreWithApp:app2];
  FIRDocumentReference *docRef2 = [firestore2 documentWithPath:doc.path];
  FIRDocumentSnapshot *snap = [self readDocumentForRef:docRef2 source:FIRFirestoreSourceCache];
  XCTAssertTrue(snap.exists);
}

- (void)testCanClearPersistenceAfterRestarting {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;
  FIRApp *app = firestore.app;
  NSString *appName = app.name;
  FIROptions *options = app.options;

  NSDictionary<NSString *, id> *initialData = @{@"foo" : @"42"};
  [self writeDocumentRef:doc data:initialData];

  // -clearPersistence() requires Firestore to be shut down. Shutdown FIRApp and remove the
  // firestore instance to emulate the way an end user would do this.
  [self shutdownFirestore:firestore];
  [self.firestores removeObject:firestore];
  [firestore
      clearPersistenceWithCompletion:[self completionForExpectationWithName:@"Enable network"]];
  [self awaitExpectations];
  [self deleteApp:app];

  // We restart the app with the same name and options to check that the previous instance's
  // persistent storage is actually cleared after the restart. Calling [self firestore] here would
  // create a new instance of firestore, which defeats the purpose of this test.
  [FIRApp configureWithName:appName options:options];
  FIRApp *app2 = [FIRApp appNamed:appName];
  FIRFirestore *firestore2 = [self firestoreWithApp:app2];
  FIRDocumentReference *docRef2 = [firestore2 documentWithPath:doc.path];
  XCTestExpectation *expectation2 = [self expectationWithDescription:@"getData"];
  [docRef2 getDocumentWithSource:FIRFirestoreSourceCache
                      completion:^(FIRDocumentSnapshot *doc2, NSError *_Nullable error) {
                        XCTAssertNotNil(error);
                        XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
                        XCTAssertEqual(error.code, FIRFirestoreErrorCodeUnavailable);
                        [expectation2 fulfill];
                      }];
  [self awaitExpectations];
}

- (void)testClearPersistenceWhileRunningFails {
  FIRDocumentReference *doc = [self documentRef];
  FIRFirestore *firestore = doc.firestore;

  [self enableNetwork];
  XCTestExpectation *expectation = [self expectationWithDescription:@"clearPersistence"];
  [firestore clearPersistenceWithCompletion:^(NSError *_Nullable error) {
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, FIRFirestoreErrorDomain);
    XCTAssertEqual(error.code, FIRFirestoreErrorCodeFailedPrecondition);
    [expectation fulfill];
  }];
  [self awaitExpectations];
}

@end
