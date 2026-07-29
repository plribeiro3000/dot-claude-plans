<!-- Fetched verbatim (via WebFetch) from
     https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html
     on 2026-07-28. Preserved here so SPIKE.md quotes stay checkable without a re-fetch. -->

# Examples of lifecycle policies in Amazon ECR

The following are example lifecycle policies showing the syntax.

To see more information about policy properties, see Lifecycle policy properties in Amazon ECR. For instructions about creating a lifecycle policy by using the AWS CLI, see To create a lifecycle policy (AWS CLI).

## Lifecycle policy template

The contents of your lifecycle policy are evaluated before being associated with a repository. The following is the JSON syntax template for the lifecycle policy.

```
{
        "rules": [
            {
                "rulePriority": {{integer}},
                "description": "{{string}}",
                "selection": {
                    "tagStatus": "{{tagged}}"|"{{untagged}}"|"{{any}}",
                    "tagPatternList": {{list<string>}},
                    "tagPrefixList": {{list<string>}},
                    "storageClass": "{{standard}}"|"{{archive}}",
                    "countType": "{{imageCountMoreThan}}"|"{{sinceImagePushed}}"|"{{sinceImagePulled}}"|"{{sinceImageTransitioned}}",
                    "countUnit": "{{string}}",
                    "countNumber": {{integer}}
                },
                "action": {
                    "type": "{{expire}}"|"{{transition}}",
                    "targetStorageClass": "{{archive}}"
                }
            }
        ]
    }
```

## Filtering on image age

The following example shows the lifecycle policy syntax for a policy that expires images with a tag starting with `prod` by using a `tagPatternList` of `prod*` that are also older than `14` days.

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire images older than 14 days",
            "selection": {
                "tagStatus": "tagged",
                "tagPatternList": ["prod*"],
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 14
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
```

## Filtering on last pulled time

The following example shows the lifecycle policy syntax for a policy that transitions images to archive storage that haven't been pulled in `90` days.

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Archive images not pulled in 90 days",
            "selection": {
                "tagStatus": "any",
                "countType": "sinceImagePulled",
                "countUnit": "days",
                "countNumber": 90
            },
            "action": {
                "type": "transition",
                "targetStorageClass": "archive"
            }
        }
    ]
}
```

**Important**
The `sinceImagePulled` count type must be used with the `transition` action. It cannot be used with the `expire` action. To delete images based on pull activity, first transition them to archive storage using `sinceImagePulled`, then use `sinceImageTransitioned` with an `expire` action to delete them. Images must be in archive storage for a minimum of 90 days before deletion.

## Filtering on archive transition time

The following example shows the lifecycle policy syntax for a policy that expires archived images that have been in archive storage for more than `365` days.

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire images archived for more than 365 days",
            "selection": {
                "tagStatus": "any",
                "storageClass": "archive",
                "countType": "sinceImageTransitioned",
                "countUnit": "days",
                "countNumber": 365
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
```

**Important**
The `sinceImageTransitioned` count type must be used with the `expire` action and the `archive` storage class. Images must be in archive storage for a minimum of 90 days before deletion.

## Filtering on image count

The following example shows the lifecycle policy syntax for a policy that keeps only one untagged image and expires all others.

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep only one untagged image, expire all others",
            "selection": {
                "tagStatus": "untagged",
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
```

## Filtering on multiple rules

The following examples use multiple rules in a lifecycle policy. An example repository and lifecycle policy are given along with an explanation of the outcome.

### Example A

Repository contents:
- Image A, Taglist: ["beta-1", "prod-1"], Pushed: 10 days ago
- Image B, Taglist: ["beta-2", "prod-2"], Pushed: 9 days ago
- Image C, Taglist: ["beta-3"], Pushed: 8 days ago

Lifecycle policy text:

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Rule 1",
            "selection": {
                "tagStatus": "tagged",
                "tagPatternList": ["prod*"],
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": { "type": "expire" }
        },
        {
            "rulePriority": 2,
            "description": "Rule 2",
            "selection": {
                "tagStatus": "tagged",
                "tagPatternList": ["beta*"],
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": { "type": "expire" }
        }
    ]
}
```

The logic of this lifecycle policy would be:
- Rule 1 identifies images tagged with prefix `prod`. It should mark images, starting with the oldest, until there is one or fewer images remaining that match. It marks Image A for expiration.
- Rule 2 identifies images tagged with prefix `beta`. It should mark images, starting with the oldest, until there is one or fewer images remaining that match. It marks both Image A and Image B for expiration. However, Image A has already been seen by Rule 1 and if Image B were expired it would violate Rule 1 and thus is skipped.
- Result: Image A is expired.

(Example B, and the multi-tag-pattern / all-images examples, follow the identical rule-priority-wins-and-freezes-earlier-matches logic — omitted here for brevity; see the live doc for the full walkthrough.)

## Archive examples

### Archiving images older than a specified number of days

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Archive production images older than 30 days",
            "selection": {
                "tagStatus": "tagged",
                "tagPatternList": ["prod*"],
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 30
            },
            "action": {
                "type": "transition",
                "targetStorageClass": "archive"
            }
        }
    ]
}
```

### Combining archive and expire rules

```json
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Archive images older than 30 days",
            "selection": {
                "tagStatus": "any",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 30
            },
            "action": {
                "type": "transition",
                "targetStorageClass": "archive"
            }
        },
        {
            "rulePriority": 2,
            "description": "Expire images archived for more than 365 days",
            "selection": {
                "tagStatus": "any",
                "storageClass": "archive",
                "countType": "sinceImageTransitioned",
                "countUnit": "days",
                "countNumber": 365
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
```

**Note**
Archived images have a minimum storage duration of 90 days. You cannot configure lifecycle policies that delete images that have been in archive for less than 90 days. If you must delete images that have been archived for less than 90 days, you need to use the **batch-delete-image** API, but you will be charged for the 90-day minimum storage duration.
