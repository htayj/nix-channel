// Install check: a consumer outside the build tree imports the installed
// package by name, compiles against its declarations and runs.
import { Either, Option, Try } from "scala-ts";

function check(condition: boolean, what: string): void {
  if (!condition) {
    throw new Error("scala-ts consumer check failed: " + what);
  }
}

const some = Option.Option<number>(20).map(n => n + 1);
check(some.isDefined && some.getOrElse(() => 0) === 21, "Option.map");
check(Option.Option<number>(null).isEmpty, "Option of null");
check(Option.Some(1).equals(Option.Some(1)), "Some equality");
// toList goes through the installed immutable.
check(Option.Some(3).toList().size === 1, "Option.toList");

const failed = Try.Try<number>(() => {
  throw new Error("boom");
});
check(failed.isFailure, "Try of a throwing function");
check(failed.recover(e => e.message.length).get() === 4, "Try.recover");
check(Try.Success(2).map(n => n * 2).get() === 4, "Try.map");

const right: Either.Either<string, number> = Either.Right(5);
check(right.isRight && right.map(n => n + 1).getOrElse(() => 0) === 6, "Either.map");
check(Either.Left<string, number>("no").toOption().isEmpty, "Left.toOption");

console.log("scala-ts consumer check passed");
