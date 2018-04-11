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

#import "Firestore/Source/Model/FSTMutation.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#import "FIRTimestamp.h"

#import "Firestore/Source/Core/FSTSnapshotVersion.h"
#import "Firestore/Source/Model/FSTDocument.h"
#import "Firestore/Source/Model/FSTFieldValue.h"
#import "Firestore/Source/Util/FSTAssert.h"
#import "Firestore/Source/Util/FSTClasses.h"

#include "Firestore/core/src/firebase/firestore/model/document_key.h"
#include "Firestore/core/src/firebase/firestore/model/field_mask.h"
#include "Firestore/core/src/firebase/firestore/model/field_path.h"
#include "Firestore/core/src/firebase/firestore/model/field_transform.h"
#include "Firestore/core/src/firebase/firestore/model/precondition.h"
#include "Firestore/core/src/firebase/firestore/model/transform_operations.h"

using firebase::firestore::model::DocumentKey;
using firebase::firestore::model::FieldMask;
using firebase::firestore::model::FieldPath;
using firebase::firestore::model::FieldTransform;
using firebase::firestore::model::Precondition;
using firebase::firestore::model::ServerTimestampTransform;
using firebase::firestore::model::TransformOperation;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - FSTSetMutation

@implementation FSTSetMutation

- (instancetype)initWithKey:(DocumentKey)key
                      value:(FSTObjectValue *)value
               precondition:(Precondition)precondition {
  if (self = [super initWithKey:std::move(key) precondition:std::move(precondition)]) {
    _value = value;
  }
  return self;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<FSTSetMutation key=%s value=%@ precondition=%@>",
                                    self.key.ToString().c_str(), self.value,
                                    self.precondition.description()];
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTSetMutation class]]) {
    return NO;
  }

  FSTSetMutation *otherMutation = (FSTSetMutation *)other;
  return [self.key isEqual:otherMutation.key] && [self.value isEqual:otherMutation.value] &&
         self.precondition == otherMutation.precondition;
}

- (NSUInteger)hash {
  NSUInteger result = [self.key hash];
  result = 31 * result + self.precondition.Hash();
  result = 31 * result + [self.value hash];
  return result;
}

- (nullable FSTMaybeDocument *)applyTo:(nullable FSTMaybeDocument *)maybeDoc
                          baseDocument:(nullable FSTMaybeDocument *)baseDoc
                        localWriteTime:(FIRTimestamp *)localWriteTime
                        mutationResult:(nullable FSTMutationResult *)mutationResult {
  if (mutationResult) {
    FSTAssert(!mutationResult.transformResults, @"Transform results received by FSTSetMutation.");
  }

  if (!self.precondition.IsValidFor(maybeDoc)) {
    return maybeDoc;
  }

  BOOL hasLocalMutations = (mutationResult == nil);
  if (!maybeDoc || [maybeDoc isMemberOfClass:[FSTDeletedDocument class]]) {
    // If the document didn't exist before, create it.
    return [FSTDocument documentWithData:self.value
                                     key:self.key
                                 version:[FSTSnapshotVersion noVersion]
                       hasLocalMutations:hasLocalMutations];
  }

  FSTAssert([maybeDoc isMemberOfClass:[FSTDocument class]], @"Unknown MaybeDocument type %@",
            [maybeDoc class]);
  FSTDocument *doc = (FSTDocument *)maybeDoc;

  FSTAssert([doc.key isEqual:self.key], @"Can only set a document with the same key");
  return [FSTDocument documentWithData:self.value
                                   key:doc.key
                               version:doc.version
                     hasLocalMutations:hasLocalMutations];
}
@end

#pragma mark - FSTPatchMutation

@implementation FSTPatchMutation {
  FieldMask _fieldMask;
}

- (instancetype)initWithKey:(DocumentKey)key
                  fieldMask:(FieldMask)fieldMask
                      value:(FSTObjectValue *)value
               precondition:(Precondition)precondition {
  self = [super initWithKey:std::move(key) precondition:std::move(precondition)];
  if (self) {
    _fieldMask = std::move(fieldMask);
    _value = value;
  }
  return self;
}

- (const firebase::firestore::model::FieldMask &)fieldMask {
  return _fieldMask;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTPatchMutation class]]) {
    return NO;
  }

  FSTPatchMutation *otherMutation = (FSTPatchMutation *)other;
  return [self.key isEqual:otherMutation.key] && self.fieldMask == otherMutation.fieldMask &&
         [self.value isEqual:otherMutation.value] &&
         self.precondition == otherMutation.precondition;
}

- (NSUInteger)hash {
  NSUInteger result = [self.key hash];
  result = 31 * result + self.precondition.Hash();
  result = 31 * result + self.fieldMask.Hash();
  result = 31 * result + [self.value hash];
  return result;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<FSTPatchMutation key=%s mask=%s value=%@ precondition=%@>",
                                    self.key.ToString().c_str(), self.fieldMask.ToString().c_str(),
                                    self.value, self.precondition.description()];
}

- (nullable FSTMaybeDocument *)applyTo:(nullable FSTMaybeDocument *)maybeDoc
                          baseDocument:(nullable FSTMaybeDocument *)baseDoc
                        localWriteTime:(FIRTimestamp *)localWriteTime
                        mutationResult:(nullable FSTMutationResult *)mutationResult {
  if (mutationResult) {
    FSTAssert(!mutationResult.transformResults, @"Transform results received by FSTPatchMutation.");
  }

  if (!self.precondition.IsValidFor(maybeDoc)) {
    return maybeDoc;
  }

  BOOL hasLocalMutations = (mutationResult == nil);
  if (!maybeDoc || [maybeDoc isMemberOfClass:[FSTDeletedDocument class]]) {
    // Precondition applied, so create the document if necessary
    const DocumentKey &key = maybeDoc ? maybeDoc.key : self.key;
    FSTSnapshotVersion *version = maybeDoc ? maybeDoc.version : [FSTSnapshotVersion noVersion];
    maybeDoc = [FSTDocument documentWithData:[FSTObjectValue objectValue]
                                         key:key
                                     version:version
                           hasLocalMutations:hasLocalMutations];
  }

  FSTAssert([maybeDoc isMemberOfClass:[FSTDocument class]], @"Unknown MaybeDocument type %@",
            [maybeDoc class]);
  FSTDocument *doc = (FSTDocument *)maybeDoc;

  FSTAssert([doc.key isEqual:self.key], @"Can only patch a document with the same key");

  FSTObjectValue *newData = [self patchObjectValue:doc.data];
  return [FSTDocument documentWithData:newData
                                   key:doc.key
                               version:doc.version
                     hasLocalMutations:hasLocalMutations];
}

- (FSTObjectValue *)patchObjectValue:(FSTObjectValue *)objectValue {
  FSTObjectValue *result = objectValue;
  for (const FieldPath &fieldPath : self.fieldMask) {
    FSTFieldValue *newValue = [self.value valueForPath:fieldPath];
    if (newValue) {
      result = [result objectBySettingValue:newValue forPath:fieldPath];
    } else {
      result = [result objectByDeletingPath:fieldPath];
    }
  }
  return result;
}

@end

@implementation FSTTransformMutation {
  /** The field transforms to use when transforming the document. */
  std::vector<FieldTransform> _fieldTransforms;
}

- (instancetype)initWithKey:(DocumentKey)key
            fieldTransforms:(std::vector<FieldTransform>)fieldTransforms {
  // NOTE: We set a precondition of exists: true as a safety-check, since we always combine
  // FSTTransformMutations with a FSTSetMutation or FSTPatchMutation which (if successful) should
  // end up with an existing document.
  if (self = [super initWithKey:std::move(key) precondition:Precondition::Exists(true)]) {
    _fieldTransforms = std::move(fieldTransforms);
  }
  return self;
}

- (const std::vector<FieldTransform> &)fieldTransforms {
  return _fieldTransforms;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTTransformMutation class]]) {
    return NO;
  }

  FSTTransformMutation *otherMutation = (FSTTransformMutation *)other;
  return [self.key isEqual:otherMutation.key] &&
         self.fieldTransforms == otherMutation.fieldTransforms &&
         self.precondition == otherMutation.precondition;
}

- (NSUInteger)hash {
  NSUInteger result = [self.key hash];
  result = 31 * result + self.precondition.Hash();
  for (const auto &transform : self.fieldTransforms) {
    result = 31 * result + transform.Hash();
  }
  return result;
}

- (NSString *)description {
  std::string fieldTransforms;
  for (const auto &transform : self.fieldTransforms) {
    fieldTransforms += " " + transform.path().CanonicalString();
  }
  return [NSString stringWithFormat:@"<FSTTransformMutation key=%s transforms=%s precondition=%@>",
                                    self.key.ToString().c_str(), fieldTransforms.c_str(),
                                    self.precondition.description()];
}

- (nullable FSTMaybeDocument *)applyTo:(nullable FSTMaybeDocument *)maybeDoc
                          baseDocument:(nullable FSTMaybeDocument *)baseDoc
                        localWriteTime:(FIRTimestamp *)localWriteTime
                        mutationResult:(nullable FSTMutationResult *)mutationResult {
  if (mutationResult) {
    FSTAssert(mutationResult.transformResults,
              @"Transform results missing for FSTTransformMutation.");
  }

  if (!self.precondition.IsValidFor(maybeDoc)) {
    return maybeDoc;
  }

  // We only support transforms with precondition exists, so we can only apply it to an existing
  // document
  FSTAssert([maybeDoc isMemberOfClass:[FSTDocument class]], @"Unknown MaybeDocument type %@",
            [maybeDoc class]);
  FSTDocument *doc = (FSTDocument *)maybeDoc;

  FSTAssert([doc.key isEqual:self.key], @"Can only patch a document with the same key");

  BOOL hasLocalMutations = (mutationResult == nil);
  NSArray<FSTFieldValue *> *transformResults =
      mutationResult
          ? mutationResult.transformResults
          : [self localTransformResultsWithBaseDocument:baseDoc writeTime:localWriteTime];
  FSTObjectValue *newData = [self transformObject:doc.data transformResults:transformResults];
  return [FSTDocument documentWithData:newData
                                   key:doc.key
                               version:doc.version
                     hasLocalMutations:hasLocalMutations];
}

/**
 * Creates an array of "transform results" (a transform result is a field value representing the
 * result of applying a transform) for use when applying an FSTTransformMutation locally.
 *
 * @param baseDocument The document prior to applying this mutation batch.
 * @param localWriteTime The local time of the transform mutation (used to generate
 * FSTServerTimestampValues).
 * @return The transform results array.
 */
- (NSArray<FSTFieldValue *> *)localTransformResultsWithBaseDocument:
                                  (FSTMaybeDocument *_Nullable)baseDocument
                                                          writeTime:(FIRTimestamp *)localWriteTime {
  NSMutableArray<FSTFieldValue *> *transformResults = [NSMutableArray array];
  for (const FieldTransform &fieldTransform : self.fieldTransforms) {
    if (fieldTransform.transformation().type() == TransformOperation::Type::ServerTimestamp) {
      FSTFieldValue *previousValue = nil;

      if ([baseDocument isMemberOfClass:[FSTDocument class]]) {
        previousValue = [((FSTDocument *)baseDocument) fieldForPath:fieldTransform.path()];
      }

      [transformResults
          addObject:[FSTServerTimestampValue serverTimestampValueWithLocalWriteTime:localWriteTime
                                                                      previousValue:previousValue]];
    } else {
      FSTFail(@"Encountered unknown transform: %d type", fieldTransform.transformation().type());
    }
  }
  return transformResults;
}

- (FSTObjectValue *)transformObject:(FSTObjectValue *)objectValue
                   transformResults:(NSArray<FSTFieldValue *> *)transformResults {
  FSTAssert(transformResults.count == self.fieldTransforms.size(),
            @"Transform results length mismatch.");

  for (size_t i = 0; i < self.fieldTransforms.size(); i++) {
    const FieldTransform &fieldTransform = self.fieldTransforms[i];
    const TransformOperation &transform = fieldTransform.transformation();
    const FieldPath &fieldPath = fieldTransform.path();
    if (transform.type() == TransformOperation::Type::ServerTimestamp) {
      objectValue = [objectValue objectBySettingValue:transformResults[i] forPath:fieldPath];
    } else {
      FSTFail(@"Encountered unknown transform: %d type", transform.type());
    }
  }
  return objectValue;
}

@end

#pragma mark - FSTDeleteMutation

@implementation FSTDeleteMutation

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[FSTDeleteMutation class]]) {
    return NO;
  }

  FSTDeleteMutation *otherMutation = (FSTDeleteMutation *)other;
  return [self.key isEqual:otherMutation.key] && self.precondition == otherMutation.precondition;
}

- (NSUInteger)hash {
  NSUInteger result = [self.key hash];
  result = 31 * result + self.precondition.Hash();
  return result;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<FSTDeleteMutation key=%s precondition=%@>",
                                    self.key.ToString().c_str(), self.precondition.description()];
}

- (nullable FSTMaybeDocument *)applyTo:(nullable FSTMaybeDocument *)maybeDoc
                          baseDocument:(nullable FSTMaybeDocument *)baseDoc
                        localWriteTime:(FIRTimestamp *)localWriteTime
                        mutationResult:(nullable FSTMutationResult *)mutationResult {
  if (mutationResult) {
    FSTAssert(!mutationResult.transformResults,
              @"Transform results received by FSTDeleteMutation.");
  }

  if (!self.precondition.IsValidFor(maybeDoc)) {
    return maybeDoc;
  }

  if (maybeDoc) {
    FSTAssert([maybeDoc.key isEqual:self.key], @"Can only delete a document with the same key");
  }

  return [FSTDeletedDocument documentWithKey:self.key version:[FSTSnapshotVersion noVersion]];
}

@end

NS_ASSUME_NONNULL_END
