; Generated from examples/let.amy

; ModuleID = 'amy-module'
source_filename = "<string>"

declare i64 @abs(i64)

define i64 @main() {
entry:
  br i1 true, label %if.then.0, label %if.else.0

if.then.0:                                        ; preds = %entry
  %0 = call i64 @f(i64 100)
  %1 = call i64 @abs(i64 %0)
  br label %if.end.0

if.else.0:                                        ; preds = %entry
  %2 = call i64 @f(i64 200)
  %3 = call i64 @abs(i64 %2)
  br label %if.end.0

if.end.0:                                         ; preds = %if.else.0, %if.then.0
  %end.0 = phi i64 [ %1, %if.then.0 ], [ %3, %if.else.0 ]
  %4 = add i64 %end.0, 2
  switch i64 %4, label %case.default.6 [
    i64 1, label %case.06
  ]

case.default.6:                                   ; preds = %if.end.0
  %5 = sub i64 %4, 3
  br label %case.end.6

case.06:                                          ; preds = %if.end.0
  br label %case.end.6

case.end.6:                                       ; preds = %case.06, %case.default.6
  %end.6 = phi i64 [ %5, %case.default.6 ], [ 2, %case.06 ]
  %6 = add i64 %end.6, %end.0
  ret i64 %6
}

define private i64 @f(i64 %x) {
entry:
  br i1 true, label %if.then.0, label %if.else.0

if.then.0:                                        ; preds = %entry
  %0 = call i64 @abs(i64 %x)
  br label %if.end.0

if.else.0:                                        ; preds = %entry
  %1 = call i64 @threeHundred()
  br label %if.end.0

if.end.0:                                         ; preds = %if.else.0, %if.then.0
  %end.0 = phi i64 [ %0, %if.then.0 ], [ %1, %if.else.0 ]
  ret i64 %end.0
}

define private i64 @threeHundred() {
entry:
  ret i64 100
}

