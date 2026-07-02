// Jenkinsfile — runs as a Docker-based Jenkins controller
//
// FLAW: Excessive S3 logging — each stage redirects its command output to a .log file
// (build.log, push.log, deploy.log) and uploads it to S3 via aws s3 cp on every build,
// in addition to Jenkins' own console log. Three extra PutObject calls per run with no
// lifecycle expiry on the pipeline/ prefix means objects accumulate indefinitely,
// inflating S3 storage and request costs. Fix: remove the aws s3 cp lines, or add an
// S3 lifecycle rule expiring pipeline/ objects after 30 days.
pipeline {
    agent any

    environment {
        AWS_REGION    = 'eu-central-1'

        // Jenkins credentials
        ECR_REGISTRY  = credentials('ecr-registry-url')
        SNS_TOPIC_ARN = credentials('sns-topic-arn')
        LOG_BUCKET    = credentials('log-bucket-name')

        // Application settings
        ECR_REPO      = 'cloud-app'
        ECS_CLUSTER   = 'cloud-app-cluster'
        ECS_SERVICE   = 'cloud-app-svc'
    }

    stages {
        stage('Checkout') {
      steps {
        checkout scm
      }
        }

        stage('Build image') {
      steps {
        sh '''
                    docker build \
                        -f Docker/Dockerfile \
                        -t ${ECR_REPO}:${BUILD_NUMBER} . \
                        > build.log 2>&1

                    cat build.log

                    aws s3 cp build.log \
                        s3://${LOG_BUCKET}/pipeline/docker-build/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Push to ECR') {
      steps {
        sh '''
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login \
                        --username AWS \
                        --password-stdin ${ECR_REGISTRY}

                    docker tag \
                        ${ECR_REPO}:${BUILD_NUMBER} \
                        ${ECR_REGISTRY}/${ECR_REPO}:${BUILD_NUMBER}

                    docker tag \
                        ${ECR_REPO}:${BUILD_NUMBER} \
                        ${ECR_REGISTRY}/${ECR_REPO}:latest

                    docker push \
                        ${ECR_REGISTRY}/${ECR_REPO}:${BUILD_NUMBER} \
                        > push.log 2>&1

                    docker push \
                        ${ECR_REGISTRY}/${ECR_REPO}:latest \
                        >> push.log 2>&1

                    cat push.log

                    aws s3 cp push.log \
                        s3://${LOG_BUCKET}/pipeline/docker-push/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Deploy to ECS') {
      steps {
        sh '''
                    aws ecs update-service \
                        --cluster ${ECS_CLUSTER} \
                        --service ${ECS_SERVICE} \
                        --force-new-deployment \
                        --region ${AWS_REGION} \
                        > deploy.log 2>&1

                    cat deploy.log

                    aws s3 cp deploy.log \
                        s3://${LOG_BUCKET}/pipeline/deploy/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Health check') {
      environment {
        ALB_DNS_NAME = credentials('app-alb-dns-name')
      }

      steps {
        sh 'bash scripts/verify_health.sh'
      }
        }
    }

    post {
        success {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline SUCCESS: build ${BUILD_NUMBER}" \
                    --message "Deployment of build ${BUILD_NUMBER} succeeded." \
                    --region ${AWS_REGION}
            '''
        }

        failure {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline FAILURE: build ${BUILD_NUMBER}" \
                    --message "Build ${BUILD_NUMBER} failed. Check Jenkins console output." \
                    --region ${AWS_REGION}
            '''
        }

        unstable {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline UNSTABLE: build ${BUILD_NUMBER}" \
                    --message "Build ${BUILD_NUMBER} completed with warnings." \
                    --region ${AWS_REGION}
            '''
        }
    }
}
